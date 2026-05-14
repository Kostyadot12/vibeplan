import Foundation

// MARK: – Auth

struct AuthRequestCodePayload: Encodable { let email: String }
struct AuthRequestCodeResponse: Decodable { let ok: Bool; let ttlMinutes: Int }

struct AuthVerifyPayload: Encodable { let email: String; let code: String }

struct AuthVerifyResponse: Decodable {
    let token: String
    let user: UserDTO
}

struct UserDTO: Codable {
    let id: String
    let email: String
    let name: String
    let role: String      // "admin" | "member"
}

// MARK: – Tasks

struct TaskDTO: Codable {
    let id: String
    let title: String
    let note: String
    let startDate: Date
    let durationMinutes: Int
    let category: String  // "personal" | "work" | "urgent" | "ideas" | "learning"
    let status: String    // "open" | "inProgress" | "done"
    let sortOrder: Int
    let inInbox: Bool
    let createdAt: Date
    let updatedAt: Date
    let subtasks: [SubtaskDTO]
    let assignees: [AssigneeDTO]
}

struct SubtaskDTO: Codable {
    let id: String
    let title: String
    let done: Bool
    let order: Int
}

struct AssigneeDTO: Codable, Hashable {
    let id: String
    let email: String
    let name: String
}

/// POST /tasks body. `id` is optional — if omitted, server generates.
struct TaskCreatePayload: Encodable {
    let title: String
    let note: String
    let startDate: Date
    let durationMinutes: Int
    let category: String
    let status: String
    let sortOrder: Int
    let inInbox: Bool
    let subtasks: [SubtaskCreatePayload]
    let assigneeIds: [String]
}

struct SubtaskCreatePayload: Encodable {
    let title: String
    let done: Bool
    let order: Int
}

/// PATCH /tasks/:id body — every field optional.
struct TaskPatchPayload: Encodable {
    var title: String?
    var note: String?
    var startDate: Date?
    var durationMinutes: Int?
    var category: String?
    var status: String?
    var sortOrder: Int?
    var inInbox: Bool?
    var subtasks: [SubtaskCreatePayload]?
    var assigneeIds: [String]?
}

/// `GET /team` — list of users available for assignment.
struct TeamMemberDTO: Codable, Hashable, Identifiable {
    let id: String
    let email: String
    let name: String
    let role: String
}
