import SwiftUI
import SwiftData

struct MainWindowView: View {
    @Environment(\.modelContext) private var ctx

    @State private var selectedDate: Date = CalendarUtil.startOfDay(.now)
    @State private var monthAnchor: Date  = CalendarUtil.startOfMonth(.now)
    @State private var editingTask: PlanTask?
    @State private var addingForDate: Date?
    @State private var dragState = DragState()
    @State private var inboxExpanded: Bool = false

    var body: some View {
        ZStack {
            VibePlanTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ToolbarBar(
                    onToday: goToToday,
                    onAdd: { addingForDate = selectedDate }
                )
                Divider().opacity(0.4)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        MonthGridView(
                            monthAnchor: $monthAnchor,
                            selectedDate: $selectedDate
                        )
                        .frame(maxHeight: .infinity)

                        InboxBar(expanded: $inboxExpanded, onEdit: { editingTask = $0 })
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }
                    .frame(minWidth: 700)

                    Divider().opacity(0.4)

                    DayPanelView(
                        date: selectedDate,
                        onEdit:   { editingTask = $0 },
                        onAddTap: { addingForDate = selectedDate }
                    )
                    .frame(width: 420)
                }
            }
        }
        .environment(dragState)
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(mode: .edit(task))
                .frame(minWidth: 520, minHeight: 680)
        }
        .sheet(item: Binding(
            get: { addingForDate.map { DateBox(date: $0) } },
            set: { addingForDate = $0?.date }
        )) { box in
            TaskEditorSheet(mode: .add(defaultDate: box.date))
                .frame(minWidth: 520, minHeight: 680)
        }
    }

    private func goToToday() {
        let today = CalendarUtil.startOfDay(.now)
        selectedDate = today
        monthAnchor = CalendarUtil.startOfMonth(today)
    }
}

/// Wrap a Date as Identifiable so we can drive a sheet from an optional Date.
private struct DateBox: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

// MARK: – Toolbar

private struct ToolbarBar: View {
    let onToday: () -> Void
    let onAdd: () -> Void

    @State private var scope: Int = 1 // 0 personal, 1 team — stub for Phase 1

    var body: some View {
        HStack(spacing: 12) {
            // Scope switch (cosmetic until Phase 3)
            HStack(spacing: 0) {
                scopeButton("Личные", index: 0)
                scopeButton("Командные", index: 1)
            }
            .padding(3)
            .background(Color.black.opacity(0.06), in: Capsule())

            // Search placeholder
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Поиск…")
                Spacer()
            }
            .font(.system(size: 13))
            .foregroundStyle(VibePlanTheme.ink400)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .frame(maxWidth: 320)
            .background(.white.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.06)))

            Spacer()

            Button(action: onToday) {
                Label("Сегодня", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.08)))

            Button(action: onAdd) {
                Label("Задача", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(VibePlanTheme.ink900, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func scopeButton(_ title: String, index: Int) -> some View {
        Button(action: { scope = index }) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(scope == index ? Color.white : Color.clear)
                        .shadow(color: scope == index ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(scope == index ? VibePlanTheme.ink900 : VibePlanTheme.ink500)
    }
}
