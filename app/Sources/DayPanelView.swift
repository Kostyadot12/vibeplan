import SwiftUI
import SwiftData

struct DayPanelView: View {
    let date: Date
    let onEdit: (PlanTask) -> Void
    let onAddTap: () -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(DragState.self) private var dragState
    @Query private var allTasks: [PlanTask]

    private let firstHour = 7
    private let lastHour  = 22

    private var dayTasks: [PlanTask] {
        allTasks
            .filter { !$0.inInbox && CalendarUtil.isSameDay($0.startDate, date) }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                timeline
                    .padding(.horizontal, 18)

                addButton
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
        }
        .background(Color.white.opacity(0.35))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(VibePlanTheme.ink900)
                Spacer()
            }
            Text(dayCaption)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(VibePlanTheme.ink500)

            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(VibePlanTheme.ink500)
                .padding(.top, 8)
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(firstHour...lastHour, id: \.self) { hour in
                HourRow(
                    hour: hour,
                    isNowMarker: isCurrentHour(hour),
                    tasks: dayTasks.filter { CalendarUtil.ru.component(.hour, from: $0.startDate) == hour },
                    onEdit: onEdit,
                    onToggleStatus: toggleStatus,
                    onDelete: delete
                )
            }
        }
    }

    private var addButton: some View {
        Button(action: onAddTap) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Добавить задачу на этот день")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(VibePlanTheme.ink500)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(Color.black.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleStatus(_ task: PlanTask) {
        task.status = task.status.next()
        try? ctx.save()
    }

    private func delete(_ task: PlanTask) {
        ctx.delete(task)
        try? ctx.save()
    }

    private func isCurrentHour(_ hour: Int) -> Bool {
        guard CalendarUtil.isSameDay(date, .now) else { return false }
        return CalendarUtil.ru.component(.hour, from: .now) == hour
    }

    private var dayTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }

    private var dayCaption: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE"
        var s = f.string(from: date)
        let rel = relativeWord()
        if !rel.isEmpty { s += " · " + rel }
        return s
    }

    private func relativeWord() -> String {
        if CalendarUtil.isSameDay(date, .now) { return "сегодня" }
        let cal = CalendarUtil.ru
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: .now),
           CalendarUtil.isSameDay(date, tomorrow) { return "завтра" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: .now),
           CalendarUtil.isSameDay(date, yesterday) { return "вчера" }
        return ""
    }

    private var summary: String {
        let total = dayTasks.count
        if total == 0 { return "Свободно — день без задач." }
        let done = dayTasks.filter { $0.status == .done }.count
        let progress = dayTasks.filter { $0.status == .inProgress }.count
        var parts: [String] = ["\(total) " + Self.taskWord(total)]
        if progress > 0 { parts.append("\(progress) в работе") }
        if done > 0 { parts.append("\(done) завершено") }
        return parts.joined(separator: " · ")
    }

    private static func taskWord(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "задача" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "задачи" }
        return "задач"
    }
}

private struct HourRow: View {
    let hour: Int
    let isNowMarker: Bool
    let tasks: [PlanTask]
    let onEdit: (PlanTask) -> Void
    let onToggleStatus: (PlanTask) -> Void
    let onDelete: (PlanTask) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(isNowMarker ? Color(red: 0.9, green: 0.33, blue: 0.33) : VibePlanTheme.ink400)
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if tasks.isEmpty {
                    Color.clear.frame(height: 56)
                } else {
                    ForEach(tasks) { task in
                        TaskCardView(
                            task: task,
                            onEdit: { onEdit(task) },
                            onToggleStatus: { onToggleStatus(task) },
                            onDelete: { onDelete(task) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isNowMarker
                      ? Color(red: 0.9, green: 0.33, blue: 0.33).opacity(0.4)
                      : Color.black.opacity(0.05))
                .frame(height: 1)
                .padding(.leading, 50)
        }
        .padding(.vertical, 4)
    }

    private var label: String {
        String(format: "%02d:00", hour)
    }
}

struct TaskCardView: View {
    let task: PlanTask
    let onEdit: () -> Void
    let onToggleStatus: () -> Void
    let onDelete: () -> Void

    @Environment(DragState.self) private var dragState

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 10) {
                StatusCircle(status: task.status)
                    .onTapGesture { onToggleStatus() }

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(task.status == .done ? VibePlanTheme.ink500 : VibePlanTheme.ink900)
                        .strikethrough(task.status == .done, color: VibePlanTheme.ink400)
                        .multilineTextAlignment(.leading)

                    Text(timeMeta)
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(VibePlanTheme.ink500)

                    if !task.note.isEmpty {
                        Text(task.note)
                            .font(.system(size: 12))
                            .foregroundStyle(VibePlanTheme.ink500)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }

                    if !task.subtasks.isEmpty {
                        SubtaskList(subtasks: task.subtasks)
                            .padding(.top, 4)
                    }

                    HStack(spacing: 8) {
                        CategoryTag(category: task.category)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06))
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(task.category.color)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
            }
            .shadow(color: .black.opacity(task.status == .done ? 0 : 0.08), radius: 6, x: 0, y: 2)
            .opacity(task.status == .done ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Редактировать", action: onEdit)
            Button("Следующий статус", action: onToggleStatus)
            Divider()
            Button("Удалить", role: .destructive, action: onDelete)
        }
        .onDrag {
            dragState.dragged = task
            return NSItemProvider(object: NSString(string: "vibeplan.task"))
        } preview: {
            HStack(spacing: 8) {
                Circle().fill(task.category.color).frame(width: 6, height: 6)
                Text(task.title).font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.1)))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch task.status {
        case .done:
            Color.black.opacity(0.03)
        case .inProgress:
            LinearGradient(
                colors: [task.category.color.opacity(0.10), Color.white],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .open:
            Color.white
        }
    }

    private var timeMeta: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        let start = f.string(from: task.startDate)
        let end = f.string(from: task.endDate)
        return "\(start) – \(end) · \(task.durationMinutes) мин"
    }
}

private struct StatusCircle: View {
    let status: PlanStatus

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(borderColor, lineWidth: 1.5)
                .frame(width: 18, height: 18)
                .background(fillView)
                .clipShape(Circle())

            if status == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var fillView: some View {
        switch status {
        case .open:
            Color.clear
        case .inProgress:
            // 60% conic fill, visually a "partial circle"
            Circle()
                .trim(from: 0, to: 0.6)
                .rotation(.degrees(-90))
                .fill(VibePlanTheme.catWork)
                .padding(2)
        case .done:
            VibePlanTheme.ink900
        }
    }

    private var borderColor: Color {
        switch status {
        case .open:       return VibePlanTheme.ink300
        case .inProgress: return VibePlanTheme.catWork
        case .done:       return VibePlanTheme.ink900
        }
    }
}

private struct CategoryTag: View {
    let category: PlanCategory

    var body: some View {
        Text(category.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(category.color.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(category.tintBackground, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct SubtaskList: View {
    let subtasks: [Subtask]
    @Environment(\.modelContext) private var ctx

    private var sorted: [Subtask] { subtasks.sorted { $0.order < $1.order } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sorted) { sub in
                HStack(spacing: 7) {
                    miniBox(done: sub.done)
                        .onTapGesture {
                            sub.done.toggle()
                            try? ctx.save()
                        }
                    Text(sub.title)
                        .font(.system(size: 12))
                        .foregroundStyle(sub.done ? VibePlanTheme.ink400 : VibePlanTheme.ink700)
                        .strikethrough(sub.done, color: VibePlanTheme.ink400)
                }
            }
        }
    }

    private func miniBox(done: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(done ? VibePlanTheme.ink900 : VibePlanTheme.ink300, lineWidth: 1.5)
                .background(done ? VibePlanTheme.ink900 : Color.clear, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                .frame(width: 13, height: 13)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Rectangle())
    }
}
