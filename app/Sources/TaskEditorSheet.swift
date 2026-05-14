import SwiftUI
import SwiftData

enum EditorMode {
    case add(defaultDate: Date)
    case edit(PlanTask)
}

struct TaskEditorSheet: View {
    let mode: EditorMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var dateOnly: Date = .now
    @State private var time: Date = .now
    @State private var durationMinutes: Int = 30
    @State private var category: PlanCategory = .work
    @State private var status: PlanStatus = .open
    @State private var subtaskDrafts: [SubtaskDraft] = []
    @State private var newSubtaskText: String = ""

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleField
                    timeRow
                    pickerRow
                    noteField
                    subtasksSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .background(Color(white: 0.97))
        .onAppear(perform: load)
    }

    // MARK: – Sections

    private var header: some View {
        HStack {
            Text(isEdit ? "Редактировать задачу" : "Новая задача")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VibePlanTheme.ink500)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.0001))
        }
        .padding(16)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Название")
            TextField("Что нужно сделать?", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08)))
        }
    }

    private var timeRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                label("Дата")
                DatePicker("", selection: $dateOnly, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            VStack(alignment: .leading, spacing: 6) {
                label("Время")
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            VStack(alignment: .leading, spacing: 6) {
                label("Длительность")
                Stepper(value: $durationMinutes, in: 15...480, step: 15) {
                    Text("\(durationMinutes) мин")
                        .font(.system(size: 13).monospacedDigit())
                        .frame(width: 70, alignment: .leading)
                }
            }
            Spacer()
        }
    }

    private var pickerRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                label("Категория")
                Picker("", selection: $category) {
                    ForEach(PlanCategory.allCases) { c in
                        HStack {
                            Circle().fill(c.color).frame(width: 8, height: 8)
                            Text(c.label)
                        }
                        .tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("Статус")
                Picker("", selection: $status) {
                    ForEach(PlanStatus.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
            }
            Spacer()
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Заметка")
            TextEditor(text: $note)
                .font(.system(size: 13))
                .frame(minHeight: 70, maxHeight: 120)
                .padding(8)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.08)))
        }
    }

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Подзадачи")
            VStack(spacing: 6) {
                ForEach($subtaskDrafts) { $draft in
                    HStack(spacing: 8) {
                        Button {
                            draft.done.toggle()
                        } label: {
                            Image(systemName: draft.done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(draft.done ? VibePlanTheme.ink900 : VibePlanTheme.ink400)
                        }
                        .buttonStyle(.plain)

                        TextField("Подзадача", text: $draft.title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))

                        Button {
                            subtaskDrafts.removeAll { $0.id == draft.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(VibePlanTheme.ink400)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.06)))
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .foregroundStyle(VibePlanTheme.ink400)
                    TextField("Добавить подзадачу", text: $newSubtaskText, onCommit: addSubtask)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    Button("Добавить", action: addSubtask)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(newSubtaskText.isEmpty ? VibePlanTheme.ink400 : VibePlanTheme.ink900)
                        .disabled(newSubtaskText.isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var footer: some View {
        HStack {
            if isEdit {
                Button("Удалить", role: .destructive, action: deleteAndClose)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            Spacer()
            Button("Отмена", action: { dismiss() })
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.1)))

            Button(isEdit ? "Сохранить" : "Создать", action: save)
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(VibePlanTheme.ink900, in: Capsule())
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(14)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(VibePlanTheme.ink500)
    }

    // MARK: – Actions

    private func addSubtask() {
        let s = newSubtaskText.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        subtaskDrafts.append(SubtaskDraft(title: s, done: false))
        newSubtaskText = ""
    }

    private func load() {
        switch mode {
        case .add(let defaultDate):
            let cal = CalendarUtil.ru
            dateOnly = defaultDate
            // default time: next round half-hour
            let now = Date()
            var comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
            comps.minute = (cal.component(.minute, from: now) < 30) ? 30 : 0
            if comps.minute == 0 { comps.hour = (comps.hour ?? 0) + 1 }
            time = cal.date(from: comps) ?? now

            // if default day != today, pin time to 09:00
            if !CalendarUtil.isSameDay(defaultDate, .now) {
                var pin = cal.dateComponents([.year, .month, .day], from: defaultDate)
                pin.hour = 9
                pin.minute = 0
                time = cal.date(from: pin) ?? defaultDate
            }

        case .edit(let task):
            title = task.title
            note = task.note
            dateOnly = task.startDate
            time = task.startDate
            durationMinutes = task.durationMinutes
            category = task.category
            status = task.status
            subtaskDrafts = task.subtasks
                .sorted { $0.order < $1.order }
                .map { SubtaskDraft(title: $0.title, done: $0.done) }
        }
    }

    private func save() {
        let merged = mergeDateAndTime()
        switch mode {
        case .add:
            let task = PlanTask(
                title: title,
                note: note,
                startDate: merged,
                durationMinutes: durationMinutes,
                category: category,
                status: status
            )
            task.subtasks = subtaskDrafts.enumerated().map { idx, d in
                Subtask(title: d.title, done: d.done, order: idx)
            }
            ctx.insert(task)

        case .edit(let task):
            task.title = title
            task.note = note
            task.startDate = merged
            task.durationMinutes = durationMinutes
            task.category = category
            task.status = status
            // replace subtasks in-place: simplest, no diff needed
            for s in task.subtasks { ctx.delete(s) }
            task.subtasks = subtaskDrafts.enumerated().map { idx, d in
                Subtask(title: d.title, done: d.done, order: idx)
            }
        }
        try? ctx.save()
        dismiss()
    }

    private func deleteAndClose() {
        if case .edit(let task) = mode {
            ctx.delete(task)
            try? ctx.save()
        }
        dismiss()
    }

    private func mergeDateAndTime() -> Date {
        let cal = CalendarUtil.ru
        let d = cal.dateComponents([.year, .month, .day], from: dateOnly)
        let t = cal.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year   = d.year
        merged.month  = d.month
        merged.day    = d.day
        merged.hour   = t.hour
        merged.minute = t.minute
        return cal.date(from: merged) ?? Date()
    }
}

private struct SubtaskDraft: Identifiable {
    let id = UUID()
    var title: String
    var done: Bool
}
