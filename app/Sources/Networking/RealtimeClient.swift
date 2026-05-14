import Foundation
import SwiftData
import SwiftUI

/// Persistent WebSocket connection to /ws. Auto-reconnects with exponential
/// backoff. Pushes incoming `task.*` events to a callback that applies them
/// to SwiftData; ignores events that originated from this app instance
/// (echo prevention via `clientId`).
///
/// Public state (`status`, `lastError`) is mutated only on the main actor so
/// SwiftUI views observing these via `@Observable` see consistent reads.
@Observable
final class RealtimeClient {
    enum Status { case offline, connecting, live }

    @MainActor private(set) var status: Status = .offline
    @MainActor private(set) var lastError: String?

    /// Stable per-installation UUID — used by SyncEngine to label its own
    /// mutations and by the server to echo `originClientId` back. We then
    /// drop events with this id so we don't double-apply our own writes.
    static let clientId: String = {
        let key = "vibeplan.clientId"
        if let s = UserDefaults.standard.string(forKey: key) { return s }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }()

    private let auth: AuthState
    private let settings: AppSettings
    private let container: ModelContainer
    private var task: URLSessionWebSocketTask?
    private var reconnectAttempt: Int = 0
    private var reconnectWork: Task<Void, Never>?
    private var stopped: Bool = false

    /// Optional pointer to the SpacesRoster — set by App.swift so we can apply
    /// space.* events. Note: not `weak` because @Observable macros don't
    /// always play well with weak storage; the roster outlives the realtime
    /// client (both are held by App for the app's lifetime).
    var spacesRoster: SpacesRoster?

    init(auth: AuthState, settings: AppSettings, container: ModelContainer) {
        self.auth = auth
        self.settings = settings
        self.container = container
    }

    // MARK: – Public API

    @MainActor
    func start() {
        stopped = false
        connect()
    }

    @MainActor
    func stop() {
        stopped = true
        reconnectWork?.cancel()
        reconnectWork = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        status = .offline
    }

    // MARK: – Connection lifecycle

    @MainActor
    private func connect() {
        guard let token = auth.token else { return }

        // Build ws:// URL from the http(s) backend URL
        guard let wsURL = makeWSURL(token: token) else {
            lastError = "Bad backend URL for WS"
            return
        }

        status = .connecting
        lastError = nil
        let req = URLRequest(url: wsURL)
        let t = URLSession.shared.webSocketTask(with: req)
        self.task = t
        t.resume()
        receive()
    }

    private func makeWSURL(token: String) -> URL? {
        guard var components = URLComponents(url: settings.backendURL, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        components.path = "/ws"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "clientId", value: Self.clientId)
        ]
        return components.url
    }

    @MainActor
    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .failure(let err):
                    self.handleFailure(err)
                case .success(let message):
                    self.handleMessage(message)
                    self.receive()    // queue next read
                }
            }
        }
    }

    @MainActor
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return }

        // Tag any non-ping/hello message as "we're live"
        if status != .live { status = .live; reconnectAttempt = 0 }

        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = envelope["type"] as? String
        else { return }

        switch type {
        case "hello", "ping":
            return    // alive signals only
        case "task.created", "task.updated":
            if let originId = envelope["originClientId"] as? String, originId == Self.clientId {
                return    // our own write echoed back — ignore
            }
            if let taskJSON = envelope["task"], let raw = try? JSONSerialization.data(withJSONObject: taskJSON) {
                applyUpsert(rawTask: raw)
                if type == "task.created" {
                    notifyAboutCreate(rawTask: raw)
                } else {
                    notifyAboutUpdate(rawTask: raw)
                }
            }
        case "task.deleted":
            if let originId = envelope["originClientId"] as? String, originId == Self.clientId {
                return
            }
            if let id = envelope["id"] as? String {
                applyDelete(serverId: id)
            }
        case "space.created", "space.updated":
            if let spaceJSON = envelope["space"],
               let raw = try? JSONSerialization.data(withJSONObject: spaceJSON),
               let dto = try? Self.spaceDecoder.decode(SpaceDTO.self, from: raw) {
                spacesRoster?.upsert(dto)
            }
        case "space.deleted":
            if let id = envelope["id"] as? String {
                spacesRoster?.remove(spaceId: id)
            }
        default:
            break
        }
    }

    private static let spaceDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: s) { return d }
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            if let d = f2.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad iso8601: \(s)")
        }
        return d
    }()

    @MainActor
    private func handleFailure(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        status = .offline
        if !stopped { scheduleReconnect() }
    }

    @MainActor
    private func scheduleReconnect() {
        reconnectWork?.cancel()
        let attempt = reconnectAttempt
        reconnectAttempt = min(attempt + 1, 6)
        // 1s → 2s → 4s → 8s → 16s → 30s
        let delay: UInt64 = UInt64(min(30, 1 << attempt)) * 1_000_000_000

        reconnectWork = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run {
                guard let self, !self.stopped else { return }
                self.connect()
            }
        }
    }

    // MARK: – Apply incoming events to SwiftData

    @MainActor
    private func applyUpsert(rawTask data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date")
        }
        guard let dto = try? decoder.decode(TaskDTO.self, from: data) else { return }

        let ctx = ModelContext(container)
        let sid = dto.id
        let existing = try? ctx.fetch(FetchDescriptor<PlanTask>(
            predicate: #Predicate { $0.serverId == sid }
        )).first

        if let task = existing {
            task.apply(dto)
        } else {
            let newTask = PlanTask.fromRemote(dto)
            ctx.insert(newTask)
        }
        try? ctx.save()
    }

    @MainActor
    private func notifyAboutCreate(rawTask data: Data) {
        guard let dto = decodeTask(data), let me = auth.user?.id else { return }
        let isAssigned = dto.assignees.contains(where: { $0.id == me })
        guard isAssigned else { return }   // only ping if it concerns me
        let creatorName = creatorDisplayName(dto.creatorId) ?? "Кто-то"
        Notifier.post(
            title: "Новая задача от \(creatorName)",
            body:  dto.title
        )
    }

    @MainActor
    private func notifyAboutUpdate(rawTask data: Data) {
        guard let dto = decodeTask(data), let me = auth.user?.id else { return }
        guard dto.assignees.contains(where: { $0.id == me }) else { return }
        // Throttle: only notify on status change to .done or in_progress.
        if dto.status == "done" {
            Notifier.post(title: "Задача выполнена", body: dto.title)
        }
    }

    @MainActor
    private func decodeTask(_ data: Data) -> TaskDTO? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let v = f1.date(from: s) { return v }
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            if let v = f2.date(from: s) { return v }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad iso8601: \(s)")
        }
        return try? decoder.decode(TaskDTO.self, from: data)
    }

    @MainActor
    private func creatorDisplayName(_ creatorId: String?) -> String? {
        guard let id = creatorId else { return nil }
        // Try TeamRoster (held by App) — for now we do a lightweight lookup via SpacesRoster.
        if let roster = spacesRoster {
            for s in roster.spaces {
                if let m = s.members.first(where: { $0.userId == id }) {
                    return m.name.isEmpty ? m.email : m.name
                }
            }
        }
        return nil
    }

    @MainActor
    private func applyDelete(serverId sid: String) {
        let ctx = ModelContext(container)
        if let target = try? ctx.fetch(FetchDescriptor<PlanTask>(
            predicate: #Predicate { $0.serverId == sid }
        )).first {
            ctx.delete(target)
            try? ctx.save()
        }
    }
}
