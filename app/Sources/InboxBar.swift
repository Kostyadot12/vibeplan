import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct InboxBar: View {
    @Binding var expanded: Bool
    let searchQuery: String
    let onEdit: (PlanTask) -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(DragState.self) private var dragState
    @Environment(SyncEngine.self) private var sync
    @Query private var allTasks: [PlanTask]

    @State private var hoveringDrop: Bool = false

    private var inboxTasks: [PlanTask] {
        allTasks
            .filter { $0.inInbox && matchesSearch($0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func matchesSearch(_ task: PlanTask) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        if task.title.lowercased().contains(q) { return true }
        if task.note.lowercased().contains(q)  { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if expanded {
                listSection
                    .padding(.top, 10)
            }
        }
        .padding(14)
        .background(.white.opacity(hoveringDrop ? 0.95 : 0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(hoveringDrop ? VibePlanTheme.ink900 : Color.black.opacity(0.05),
                        style: StrokeStyle(lineWidth: hoveringDrop ? 2 : 1, dash: hoveringDrop ? [6, 4] : []))
        )
        .animation(.easeOut(duration: 0.15), value: hoveringDrop)
        .animation(.easeOut(duration: 0.18), value: expanded)
        .onDrop(of: [.text], isTargeted: $hoveringDrop) { _ in
            handleDrop()
        }
    }

    // MARK: – Header

    private var header: some View {
        Button(action: { expanded.toggle() }) {
            HStack(spacing: 10) {
                inboxIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text("Неразобранное")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VibePlanTheme.ink900)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(VibePlanTheme.ink500)
                        .lineLimit(1)
                }
                Spacer()
                if !inboxTasks.isEmpty {
                    Text("\(inboxTasks.count)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 2)
                        .background(VibePlanTheme.ink900, in: Capsule())
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VibePlanTheme.ink400)
            }
        }
        .buttonStyle(.plain)
    }

    private var inboxIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(VibePlanTheme.catUrgent.opacity(0.15))
                .frame(width: 32, height: 32)
            Image(systemName: "tray.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VibePlanTheme.catUrgent)
        }
    }

    private var subtitle: String {
        if inboxTasks.isEmpty {
            return "пусто — задачи без даты будут попадать сюда"
        }
        return "перетащите на день в календаре"
    }

    // MARK: – List

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if inboxTasks.isEmpty {
                Text("Перетащите сюда любую задачу из календаря, чтобы убрать её из расписания.")
                    .font(.system(size: 12))
                    .foregroundStyle(VibePlanTheme.ink500)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(inboxTasks) { task in
                    InboxRow(task: task, onEdit: { onEdit(task) }, onDelete: { delete(task) })
                }
            }
        }
    }

    // MARK: – Actions

    private func handleDrop() -> Bool {
        guard let task = dragState.dragged else { return false }
        task.inInbox = true
        try? ctx.save()
        sync.pushUpdate(task)
        dragState.dragged = nil
        expanded = true
        return true
    }

    private func delete(_ task: PlanTask) {
        let sid = task.serverId
        ctx.delete(task)
        try? ctx.save()
        sync.pushDelete(serverId: sid)
    }
}

private struct InboxRow: View {
    let task: PlanTask
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(DragState.self) private var dragState

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 10) {
                Circle().fill(task.category.color).frame(width: 8, height: 8)
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VibePlanTheme.ink900)
                Spacer()
                Text(task.category.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(task.category.color.opacity(0.9))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(task.category.tintBackground, in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Редактировать", action: onEdit)
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
}
