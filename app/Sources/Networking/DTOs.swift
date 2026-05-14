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
    let creatorId: String?
    let spaceId:   String?
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
    let spaceId: String?
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
    var spaceId: String??     // Double-optional so we can patch to null explicitly
    var subtasks: [SubtaskCreatePayload]?
    var assigneeIds: [String]?

    enum CodingKeys: String, CodingKey {
        case title, note, startDate, durationMinutes, category, status
        case sortOrder, inInbox, spaceId, subtasks, assigneeIds
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try c.encodeIfPresent(inInbox, forKey: .inInbox)
        // Double-optional: emit only if outer set; emit explicit null if inner nil
        if let inner = spaceId {
            if let v = inner { try c.encode(v, forKey: .spaceId) }
            else { try c.encodeNil(forKey: .spaceId) }
        }
        try c.encodeIfPresent(subtasks, forKey: .subtasks)
        try c.encodeIfPresent(assigneeIds, forKey: .assigneeIds)
    }
}

/// `GET /team` — list of users available for assignment.
struct TeamMemberDTO: Codable, Hashable, Identifiable {
    let id: String
    let email: String
    let name: String
    let role: String
}

// MARK: – Spaces

struct SpaceDTO: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let color: String
    let ownerId: String
    let createdAt: Date
    let members: [SpaceMemberDTO]
}

struct SpaceMemberDTO: Codable, Hashable, Identifiable {
    let userId: String
    let email: String
    let name: String
    let role: String
    let joinedAt: Date

    var id: String { userId }
}

struct SpaceCreatePayload: Encodable {
    let name: String
    let color: String
}

struct SpacePatchPayload: Encodable {
    var name:  String?
    var color: String?
}

struct SpaceInvitePayload: Encodable {
    let email: String
    let role: String
}

struct SpaceInviteResponse: Decodable {
    let invited: Bool?
    let email:   String?
    let hasAccount: Bool?
    let pending: Bool?
    // If user existed and was added immediately, the API returns the
    // updated SpaceDTO. We try-decode both shapes upstream.
}
