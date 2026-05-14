import Foundation
import SwiftData
import SwiftUI

@Model
final class PlanTask {
    var title: String
    var note: String
    var startDate: Date
    var durationMinutes: Int
    var categoryRaw: String
    var statusRaw: String
    var sortOrder: Int
    var createdAt: Date
    var inInbox: Bool = false

    /// Server-assigned id once this task has been synced. nil → never pushed.
    var serverId: String? = nil

    /// Server id of the space this task belongs to. nil → personal (creator only).
    var spaceServerId: String? = nil

    /// Server id of the user who created this task.
    var creatorServerId: String? = nil

    @Relationship(deleteRule: .cascade)
    var subtasks: [Subtask] = []

    @Relationship(deleteRule: .cascade)
    var assignees: [TaskAssignee] = []

    init(
        title: String,
        note: String = "",
        startDate: Date,
        durationMinutes: Int = 30,
        category: PlanCategory = .work,
        status: PlanStatus = .open,
        sortOrder: Int = 0,
        inInbox: Bool = false,
        serverId: String? = nil,
        spaceServerId: String? = nil,
        creatorServerId: String? = nil
    ) {
        self.title = title
        self.note = note
        self.startDate = startDate
        self.durationMinutes = durationMinutes
        self.categoryRaw = category.rawValue
        self.statusRaw = status.rawValue
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.inInbox = inInbox
        self.serverId = serverId
        self.spaceServerId = spaceServerId
        self.creatorServerId = creatorServerId
    }

    var category: PlanCategory {
        get { PlanCategory(rawValue: categoryRaw) ?? .work }
        set { categoryRaw = newValue.rawValue }
    }

    var status: PlanStatus {
        get { PlanStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var endDate: Date {
        startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

@Model
final class Subtask {
    var title: String
    var done: Bool
    var order: Int
    var serverId: String? = nil

    init(title: String, done: Bool = false, order: Int = 0, serverId: String? = nil) {
        self.title = title
        self.done = done
        self.order = order
        self.serverId = serverId
    }
}

/// Denormalized assignee — we keep user id + display info on the task itself
/// so the calendar doesn't need a roster lookup just to render avatars.
@Model
final class TaskAssignee {
    var userId: String     // matches User.id on the backend
    var email: String
    var name: String

    init(userId: String, email: String, name: String) {
        self.userId = userId
        self.email = email
        self.name = name
    }
}

/// A "space" — a folder/team with members, owns tasks visible to its members.
@Model
final class Space {
    var serverId: String
    var name: String
    var colorRaw: String     // matches PlanCategory raw values
    var ownerId: String

    @Relationship(deleteRule: .cascade)
    var members: [SpaceMember] = []

    init(serverId: String, name: String, colorRaw: String = "work", ownerId: String) {
        self.serverId = serverId
        self.name = name
        self.colorRaw = colorRaw
        self.ownerId = ownerId
    }

    var color: PlanCategory {
        PlanCategory(rawValue: colorRaw) ?? .work
    }
}

@Model
final class SpaceMember {
    var userId: String
    var email: String
    var name: String
    var role: String       // "owner" | "member"

    init(userId: String, email: String, name: String, role: String) {
        self.userId = userId
        self.email = email
        self.name = name
        self.role = role
    }
}

enum PlanCategory: String, CaseIterable, Identifiable {
    case personal
    case work
    case urgent
    case ideas
    case learning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .personal: return "Личное"
        case .work:     return "Работа"
        case .urgent:   return "Срочно"
        case .ideas:    return "Идеи"
        case .learning: return "Обучение"
        }
    }

    var color: Color {
        switch self {
        case .personal: return VibePlanTheme.catPersonal
        case .work:     return VibePlanTheme.catWork
        case .urgent:   return VibePlanTheme.catUrgent
        case .ideas:    return VibePlanTheme.catIdeas
        case .learning: return VibePlanTheme.catLearning
        }
    }

    var tintBackground: Color {
        color.opacity(0.15)
    }
}

enum PlanStatus: String, CaseIterable, Identifiable {
    case open
    case inProgress
    case done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open:       return "Открыта"
        case .inProgress: return "В работе"
        case .done:       return "Выполнена"
        }
    }

    func next() -> PlanStatus {
        switch self {
        case .open:       return .inProgress
        case .inProgress: return .done
        case .done:       return .open
        }
    }
}

enum CalendarUtil {
    static let ru: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        c.locale = Locale(identifier: "ru_RU")
        c.timeZone = .current
        return c
    }()

    static func startOfDay(_ date: Date) -> Date {
        ru.startOfDay(for: date)
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        ru.isDate(a, inSameDayAs: b)
    }

    static func startOfMonth(_ date: Date) -> Date {
        let comps = ru.dateComponents([.year, .month], from: date)
        return ru.date(from: comps) ?? date
    }

    /// 42 dates: 6 weeks × 7 days, starting from the Monday before/on the 1st.
    static func monthGridDates(for anchor: Date) -> [Date] {
        let monthStart = startOfMonth(anchor)
        let weekday = ru.component(.weekday, from: monthStart) // 1=Sun..7=Sat
        // We want Monday-start: how many days back from monthStart is Monday?
        let daysBack = (weekday - ru.firstWeekday + 7) % 7
        guard let gridStart = ru.date(byAdding: .day, value: -daysBack, to: monthStart) else {
            return []
        }
        return (0..<42).compactMap { ru.date(byAdding: .day, value: $0, to: gridStart) }
    }

    static func addMonths(_ months: Int, to date: Date) -> Date {
        ru.date(byAdding: .month, value: months, to: date) ?? date
    }
}
