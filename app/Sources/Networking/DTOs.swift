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
    let avatarUrl: String?
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
    let spaceId: String?
    let reminderMinutes: Int?
    let subtasks: [SubtaskDTO]
    let assignees: [AssigneeDTO]
    let attachments: [AttachmentDTO]
    let tagIds: [String]
}

struct CommentDTO: Codable, Hashable, Identifiable {
    let id: String
    let taskId: String
    let authorId: String?
    let body: String
    let createdAt: Date
    let updatedAt: Date
}

struct TagDTO: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let color: String
    let spaceId: String?
    let ownerId: String?
}

struct TagCreatePayload: Encodable {
    let name: String
    let color: String
    let spaceId: String?
}

struct ActivityEventDTO: Codable, Hashable, Identifiable {
    let id: String
    let spaceId: String?
    let actorId: String?
    let taskId: String?
    let kind: String
    let summary: String
    let createdAt: Date
}

struct SubtaskDTO: Codable {
    let id: String
    let title: String
    let done: Bool
    let order: Int
}

struct AttachmentDTO: Codable, Hashable, Identifiable {
    let id: String
    let filename: String
    let mimeType: String
    let sizeBytes: Int
    let url: String
    let uploadedAt: Date
    let uploadedById: String?
}

struct AssigneeDTO: Codable, Hashable {
    let id: String
    let email: String
    let name: String
    var avatarUrl: String? = nil
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
    let reminderMinutes: Int?
    let subtasks: [SubtaskCreatePayload]
    let assigneeIds: [String]
    let tagIds: [String]
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
    var spaceId: String??       // Double-optional so we can patch to null explicitly
    var reminderMinutes: Int??
    var subtasks: [SubtaskCreatePayload]?
    var assigneeIds: [String]?
    var tagIds: [String]?

    enum CodingKeys: String, CodingKey {
        case title, note, startDate, durationMinutes, category, status
        case sortOrder, inInbox, spaceId, reminderMinutes
        case subtasks, assigneeIds, tagIds
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
        if let inner = spaceId {
            if let v = inner { try c.encode(v, forKey: .spaceId) }
            else { try c.encodeNil(forKey: .spaceId) }
        }
        if let inner = reminderMinutes {
            if let v = inner { try c.encode(v, forKey: .reminderMinutes) }
            else { try c.encodeNil(forKey: .reminderMinutes) }
        }
        try c.encodeIfPresent(subtasks, forKey: .subtasks)
        try c.encodeIfPresent(assigneeIds, forKey: .assigneeIds)
        try c.encodeIfPresent(tagIds, forKey: .tagIds)
    }
}

/// `GET /team` — list of users available for assignment.
struct TeamMemberDTO: Codable, Hashable, Identifiable {
    let id: String
    let email: String
    let name: String
    let role: String
    var avatarUrl: String? = nil
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
    var avatarUrl: String? = nil

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
