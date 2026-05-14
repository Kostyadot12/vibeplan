import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case http(Int, String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Неверный URL бэкенда"
        case .http(let code, let m): return "HTTP \(code): \(m)"
        case .decoding(let e):      return "Ошибка декодирования: \(e.localizedDescription)"
        case .transport(let e):     return "Ошибка сети: \(e.localizedDescription)"
        }
    }
}

/// Stateless URLSession-based client. Token + base URL are passed per call so
/// a single instance can be reused across logins without rebuilding.
struct APIClient {
    let baseURL: URL
    let token: String?

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Backend uses ISO8601 with milliseconds (e.g. 2026-05-15T10:00:00.000Z).
        // Foundation's .iso8601 doesn't accept fractional seconds, so we use
        // a custom formatter that handles both.
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            if let d = Self.dateFormatterFractional.date(from: s) { return d }
            if let d = Self.dateFormatterPlain.date(from: s)      { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unparseable ISO8601 date: \(s)"
            )
        }
        return d
    }()

    private static let dateFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let dateFormatterPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: – Auth

    func requestCode(email: String) async throws {
        try await voidPost("auth/request-code", AuthRequestCodePayload(email: email))
    }

    func verify(email: String, code: String) async throws -> AuthVerifyResponse {
        try await post("auth/verify", AuthVerifyPayload(email: email, code: code))
    }

    func me() async throws -> UserDTO {
        try await get("me")
    }

    // MARK: – Tasks

    func listTasks() async throws -> [TaskDTO] {
        try await get("tasks")
    }

    func createTask(_ payload: TaskCreatePayload) async throws -> TaskDTO {
        try await post("tasks", payload)
    }

    func updateTask(id: String, patch: TaskPatchPayload) async throws -> TaskDTO {
        try await patchJSON("tasks/\(id)", patch)
    }

    func deleteTask(id: String) async throws {
        try await voidDelete("tasks/\(id)")
    }

    // MARK: – Internals

    private func get<R: Decodable>(_ path: String) async throws -> R {
        try await send(method: "GET", path: path, body: nil as Empty?)
    }

    private func post<B: Encodable, R: Decodable>(_ path: String, _ body: B) async throws -> R {
        try await send(method: "POST", path: path, body: body)
    }

    private func voidPost<B: Encodable>(_ path: String, _ body: B) async throws {
        let _: Empty = try await send(method: "POST", path: path, body: body)
    }

    private func patchJSON<B: Encodable, R: Decodable>(_ path: String, _ body: B) async throws -> R {
        try await send(method: "PATCH", path: path, body: body)
    }

    private func voidDelete(_ path: String) async throws {
        let _: Empty = try await send(method: "DELETE", path: path, body: nil as Empty?)
    }

    private func send<B: Encodable, R: Decodable>(method: String, path: String, body: B?) async throws -> R {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try Self.encoder.encode(body) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, body)
        }
        if R.self == Empty.self { return Empty() as! R }
        do {
            return try Self.decoder.decode(R.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

private struct Empty: Codable {}
