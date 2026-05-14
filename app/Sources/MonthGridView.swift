import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MonthGridView: View {
    @Binding var monthAnchor: Date
    @Binding var selectedDate: Date
    let searchQuery: String

    @Environment(\.modelContext)    private var ctx
    @Environment(DragState.self)    private var dragState
    @Environment(SyncEngine.self)   private var sync
    @Environment(SpacesRoster.self) private var spacesRoster
    @Query private var allTasks: [PlanTask]

    private let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    private var monthRange: (start: Date, end: Date) {
        let cal = CalendarUtil.ru
        let start = CalendarUtil.startOfMonth(monthAnchor)
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return (start, end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(VibePlanTheme.ink400)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
            }

            grid
        }
        .padding(20)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(monthName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(VibePlanTheme.ink900)
                Text(yearString)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(VibePlanTheme.ink400)
            }
            Spacer()
            HStack(spacing: 4) {
                navButton("chevron.left")  { monthAnchor = CalendarUtil.addMonths(-1, to: monthAnchor) }
                navButton("chevron.right") { monthAnchor = CalendarUtil.addMonths(1,  to: monthAnchor) }
            }
        }
    }

    private func navButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(VibePlanTheme.ink500)
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.0001))
        .contentShape(Rectangle())
    }

    private var grid: some View {
        let dates = CalendarUtil.monthGridDates(for: monthAnchor)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(dates, id: \.self) { date in
                DayCell(
                    date: date,
                    inMonth: isInDisplayedMonth(date),
                    isToday: CalendarUtil.isSameDay(date, .now),
                    isSelected: CalendarUtil.isSameDay(date, selectedDate),
                    tasks: tasks(on: date)
                )
                .onTapGesture { selectedDate = CalendarUtil.startOfDay(date) }
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    handleDrop(onto: date)
                }
            }
        }
    }

    private func handleDrop(onto date: Date) -> Bool {
        guard let task = dragState.dragged else { return false }
        let cal = CalendarUtil.ru
        // Preserve hour/minute from the task's existing startDate when re-dating.
        // If task was in inbox, use 09:00 as the default landing time.
        let timeComps: DateComponents
        if task.inInbox {
            timeComps = DateComponents(hour: 9, minute: 0)
        } else {
            timeComps = cal.dateComponents([.hour, .minute], from: task.startDate)
        }
        var dateComps = cal.dateComponents([.year, .month, .day], from: date)
        dateComps.hour   = timeComps.hour
        dateComps.minute = timeComps.minute
        if let newDate = cal.date(from: dateComps) {
            task.startDate = newDate
            task.inInbox = false
            try? ctx.save()
            sync.pushUpdate(task)
            selectedDate = CalendarUtil.startOfDay(date)
        }
        dragState.dragged = nil
        return true
    }

    private func isInDisplayedMonth(_ date: Date) -> Bool {
        let cal = CalendarUtil.ru
        return cal.component(.month, from: date) == cal.component(.month, from: monthAnchor)
            && cal.component(.year, from: date) == cal.component(.year, from: monthAnchor)
    }

    private func tasks(on date: Date) -> [PlanTask] {
        allTasks
            .filter {
                !$0.inInbox
                && CalendarUtil.isSameDay($0.startDate, date)
                && matchesScope($0, scope: spacesRoster.scope)
                && matches(searchQuery, $0)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private func matches(_ query: String, _ task: PlanTask) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        if task.title.lowercased().contains(q) { return true }
        if task.note.lowercased().contains(q)  { return true }
        if task.assignees.contains(where: { $0.name.lowercased().contains(q) || $0.email.lowercased().contains(q) }) { return true }
        return false
    }

    private var monthName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL"
        return f.string(from: monthAnchor).capitalized
    }

    private var yearString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f.string(from: monthAnchor)
    }
}

private struct DayCell: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let tasks: [PlanTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dayNumber)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(numberColor)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(tasks.prefix(3)) { task in
                    pill(for: task)
                }
                if tasks.count > 3 {
                    Text("+\(tasks.count - 3)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(moreColor)
                        .padding(.leading, 2)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: isToday ? Color.black.opacity(0.10) : .clear, radius: 6, y: 2)
    }

    private func pill(for task: PlanTask) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(task.category.color)
                .frame(width: 6, height: 6)
            Text(task.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(isSelected ? Color.white : VibePlanTheme.ink700)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.18) : Color.black.opacity(0.05))
        )
        .clipShape(Capsule(style: .continuous))
    }

    private var dayNumber: String {
        "\(CalendarUtil.ru.component(.day, from: date))"
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            VibePlanTheme.ink900
        } else if isToday {
            Color.white.opacity(0.95)
        } else if inMonth {
            Color.white.opacity(0.45)
        } else {
            Color.clear
        }
    }

    private var borderColor: Color {
        if isSelected { return VibePlanTheme.ink900 }
        if isToday { return Color.black.opacity(0.12) }
        if !inMonth { return Color.clear }
        return Color.black.opacity(0.04)
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if !inMonth   { return VibePlanTheme.ink300 }
        return VibePlanTheme.ink700
    }

    private var moreColor: Color {
        isSelected ? Color.white.opacity(0.6) : VibePlanTheme.ink400
    }
}
