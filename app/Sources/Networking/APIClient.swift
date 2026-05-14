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

    func updateMe(name: String?, avatarUrl: String??) async throws -> UserDTO {
        struct Body: Encodable {
            var name: String?
            var avatarUrl: String??
            enum CodingKeys: String, CodingKey { case name, avatarUrl }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(name, forKey: .name)
                if let inner = avatarUrl {
                    if let v = inner { try c.encode(v, forKey: .avatarUrl) }
                    else { try c.encodeNil(forKey: .avatarUrl) }
                }
            }
        }
        return try await patchJSON("me", Body(name: name, avatarUrl: avatarUrl))
    }

    /// Multipart upload of a new avatar image. Returns the updated UserDTO.
    func uploadAvatar(imageData: Data, mimeType: String) async throws -> UserDTO {
        guard let url = URL(string: "me/avatar", relativeTo: baseURL) else { throw APIError.invalidURL }
        let boundary = "----vibeplan-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(RealtimeClient.clientId, forHTTPHeaderField: "X-Client-Id")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        let ext = mimeType == "image/png" ? "png"
                : mimeType == "image/jpeg" ? "jpg"
                : mimeType == "image/gif" ? "gif" : "webp"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1, "no http") }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.userDecoder.decode(UserDTO.self, from: data)
    }

    private static let userDecoder = JSONDecoder()

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

    func listTeam() async throws -> [TeamMemberDTO] {
        try await get("team")
    }

    // MARK: – Attachments

    /// Multipart upload of a file attached to a task. Returns just the new
    /// AttachmentDTO; the rest of the task will arrive via WS broadcast.
    func uploadAttachment(taskId: String, fileURL: URL, mimeType: String) async throws -> AttachmentDTO {
        guard let url = URL(string: "tasks/\(taskId)/attachments", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        let boundary = "----vibeplan-att-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(RealtimeClient.clientId, forHTTPHeaderField: "X-Client-Id")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data = try Data(contentsOf: fileURL)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (respData, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1, "no http") }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, String(data: respData, encoding: .utf8) ?? "")
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? Date()
        }
        return try dec.decode(AttachmentDTO.self, from: respData)
    }

    func deleteAttachment(id: String) async throws {
        try await voidDelete("attachments/\(id)")
    }

    // MARK: – Comments

    func listComments(taskId: String) async throws -> [CommentDTO] {
        try await get("tasks/\(taskId)/comments")
    }

    func addComment(taskId: String, body: String) async throws -> CommentDTO {
        struct Body: Encodable { let body: String }
        return try await post("tasks/\(taskId)/comments", Body(body: body))
    }

    func deleteComment(id: String) async throws {
        try await voidDelete("comments/\(id)")
    }

    // MARK: – Tags

    func listTags(spaceId: String?) async throws -> [TagDTO] {
        if let sid = spaceId {
            return try await get("tags?spaceId=\(sid)")
        }
        return try await get("tags")
    }

    func createTag(name: String, color: String, spaceId: String?) async throws -> TagDTO {
        try await post("tags", TagCreatePayload(name: name, color: color, spaceId: spaceId))
    }

    func deleteTag(id: String) async throws {
        try await voidDelete("tags/\(id)")
    }

    // MARK: – Activity

    func listActivity(spaceId: String?) async throws -> [ActivityEventDTO] {
        if let sid = spaceId {
            return try await get("activity?spaceId=\(sid)")
        }
        return try await get("activity")
    }

    // MARK: – Spaces

    func listSpaces() async throws -> [SpaceDTO] {
        try await get("spaces")
    }

    func createSpace(name: String, color: String) async throws -> SpaceDTO {
        try await post("spaces", SpaceCreatePayload(name: name, color: color))
    }

    func updateSpace(id: String, patch: SpacePatchPayload) async throws -> SpaceDTO {
        try await patchJSON("spaces/\(id)", patch)
    }

    func deleteSpace(id: String) async throws {
        try await voidDelete("spaces/\(id)")
    }

    /// Returns the updated SpaceDTO if the user already had an account; nil
    /// if a pending invitation was created for a not-yet-registered email.
    func inviteToSpace(spaceId: String, email: String, role: String = "member") async throws -> SpaceDTO? {
        let payload = SpaceInvitePayload(email: email, role: role)
        guard let url = URL(string: "spaces/\(spaceId)/members", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(RealtimeClient.clientId, forHTTPHeaderField: "X-Client-Id")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try Self.invitePayloadEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.http(-1, "no http") }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        // 202 → pending; 201 → SpaceDTO
        if http.statusCode == 202 { return nil }
        return try Self.spaceDecoder.decode(SpaceDTO.self, from: data)
    }

    func removeMember(spaceId: String, userId: String) async throws {
        try await voidDelete("spaces/\(spaceId)/members/\(userId)")
    }

    private static let invitePayloadEncoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

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
        // Tag every mutation with our installation id so the server can echo
        // it back on the WebSocket and the receiving end can ignore its own writes.
        req.setValue(RealtimeClient.clientId, forHTTPHeaderField: "X-Client-Id")
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
