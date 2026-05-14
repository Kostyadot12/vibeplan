import Foundation
import SwiftData
import SwiftUI

/// Naive bidirectional sync.
/// - On login (or manual refresh): push local-only tasks (no serverId), then
///   pull all remote tasks and reconcile by serverId.
/// - On every local mutation: best-effort push (logged on failure, no retry).
///
/// Phase 5 will replace the polling mental model with WebSocket pushes.
@Observable
final class SyncEngine {
    private let auth: AuthState
    private let settings: AppSettings
    private let container: ModelContainer

    private(set) var isSyncing: Bool = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?

    init(auth: AuthState, settings: AppSettings, container: ModelContainer) {
        self.auth = auth
        self.settings = settings
        self.container = container
    }

    private var client: APIClient? {
        auth.token == nil ? nil : APIClient(baseURL: settings.backendURL, token: auth.token)
    }

    // MARK: – Full reconcile

    /// Pull all remote tasks; merge with local. Strategy:
    ///   1. Local tasks with no serverId → POST them, store returned id
    ///   2. GET /tasks → for every remote task:
    ///        - if local has serverId match → overwrite local from remote
    ///        - else → insert new local with serverId
    ///   3. Local tasks with serverId NOT in remote → assume deleted upstream → delete
    func fullSync() async {
        guard let client else { return }
        await MainActor.run { self.isSyncing = true; self.lastError = nil }
        defer { Task { @MainActor in self.isSyncing = false; self.lastSyncAt = .now } }

        do {
            // Step 1 — push unsynced local tasks
            let ctx = ModelContext(container)
            let unsynced = try ctx.fetch(FetchDescriptor<PlanTask>(
                predicate: #Predicate { $0.serverId == nil }
            ))
            for task in unsynced {
                let payload = TaskCreatePayload.from(task)
                let remote = try await client.createTask(payload)
                task.serverId = remote.id
                for (i, sub) in task.subtasks.sorted(by: { $0.order < $1.order }).enumerated() {
                    if i < remote.subtasks.count {
                        sub.serverId = remote.subtasks[i].id
                    }
                }
            }
            try ctx.save()

            // Step 2 — fetch remote and reconcile
            let remoteTasks = try await client.listTasks()
            let remoteById = Dictionary(uniqueKeysWithValues: remoteTasks.map { ($0.id, $0) })

            let local = try ctx.fetch(FetchDescriptor<PlanTask>())
            let localBySid: [String: PlanTask] = Dictionary(uniqueKeysWithValues:
                local.compactMap { t in t.serverId.map { ($0, t) } }
            )

            // Update or insert
            for (sid, remote) in remoteById {
                if let existing = localBySid[sid] {
                    existing.apply(remote)
                } else {
                    let newTask = PlanTask.fromRemote(remote)
                    ctx.insert(newTask)
                }
            }
            // Delete local tasks whose serverId is gone from remote
            for (sid, t) in localBySid where remoteById[sid] == nil {
                ctx.delete(t)
            }
            try ctx.save()
        } catch {
            await MainActor.run { self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)" }
        }
    }

    // MARK: – Per-mutation push (best-effort)

    func pushCreate(_ task: PlanTask) {
        guard let client else { return }
        let payload = TaskCreatePayload.from(task)
        let id = task.persistentModelID
        Task.detached {
            do {
                let remote = try await client.createTask(payload)
                let ctx = ModelContext(self.container)
                if let local = ctx.model(for: id) as? PlanTask {
                    local.serverId = remote.id
                    for (i, sub) in local.subtasks.sorted(by: { $0.order < $1.order }).enumerated() {
                        if i < remote.subtasks.count {
                            sub.serverId = remote.subtasks[i].id
                        }
                    }
                    try? ctx.save()
                }
            } catch {
                print("[sync] pushCreate failed: \(error)")
            }
        }
    }

    func pushUpdate(_ task: PlanTask) {
        guard let client, let sid = task.serverId else {
            // No serverId yet → treat as create
            pushCreate(task)
            return
        }
        let patch = TaskPatchPayload.from(task)
        Task.detached {
            do { _ = try await client.updateTask(id: sid, patch: patch) }
            catch { print("[sync] pushUpdate failed: \(error)") }
        }
    }

    func pushDelete(serverId: String?) {
        guard let client, let sid = serverId else { return }
        Task.detached {
            do { try await client.deleteTask(id: sid) }
            catch { print("[sync] pushDelete failed: \(error)") }
        }
    }
}

// MARK: – Mapping helpers

private extension TaskCreatePayload {
    static func from(_ task: PlanTask) -> TaskCreatePayload {
        TaskCreatePayload(
            title: task.title,
            note: task.note,
            startDate: task.startDate,
            durationMinutes: task.durationMinutes,
            category: task.category.rawValue,
            status: task.status.rawValue,
            sortOrder: task.sortOrder,
            inInbox: task.inInbox,
            subtasks: task.subtasks.sorted { $0.order < $1.order }.map {
                SubtaskCreatePayload(title: $0.title, done: $0.done, order: $0.order)
            },
            assigneeIds: task.assignees.map(\.userId)
        )
    }
}

private extension TaskPatchPayload {
    static func from(_ task: PlanTask) -> TaskPatchPayload {
        TaskPatchPayload(
            title: task.title,
            note: task.note,
            startDate: task.startDate,
            durationMinutes: task.durationMinutes,
            category: task.category.rawValue,
            status: task.status.rawValue,
            sortOrder: task.sortOrder,
            inInbox: task.inInbox,
            subtasks: task.subtasks.sorted { $0.order < $1.order }.map {
                SubtaskCreatePayload(title: $0.title, done: $0.done, order: $0.order)
            },
            assigneeIds: task.assignees.map(\.userId)
        )
    }
}

extension PlanTask {
    static func fromRemote(_ r: TaskDTO) -> PlanTask {
        let task = PlanTask(
            title: r.title,
            note: r.note,
            startDate: r.startDate,
            durationMinutes: r.durationMinutes,
            category: PlanCategory(rawValue: r.category) ?? .work,
            status:   PlanStatus(rawValue: r.status)   ?? .open,
            sortOrder: r.sortOrder,
            inInbox: r.inInbox,
            serverId: r.id
        )
        task.subtasks = r.subtasks.map {
            Subtask(title: $0.title, done: $0.done, order: $0.order, serverId: $0.id)
        }
        task.assignees = r.assignees.map {
            TaskAssignee(userId: $0.id, email: $0.email, name: $0.name)
        }
        return task
    }

    func apply(_ r: TaskDTO) {
        self.title = r.title
        self.note = r.note
        self.startDate = r.startDate
        self.durationMinutes = r.durationMinutes
        self.category = PlanCategory(rawValue: r.category) ?? .work
        self.status   = PlanStatus(rawValue: r.status)   ?? .open
        self.sortOrder = r.sortOrder
        self.inInbox = r.inInbox
        // Replace-all for subtasks/assignees (matches backend semantics)
        self.subtasks = r.subtasks.map {
            Subtask(title: $0.title, done: $0.done, order: $0.order, serverId: $0.id)
        }
        self.assignees = r.assignees.map {
            TaskAssignee(userId: $0.id, email: $0.email, name: $0.name)
        }
    }
}
