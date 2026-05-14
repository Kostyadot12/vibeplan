import SwiftUI
import SwiftData
import AppKit

enum EditorMode {
    case add(defaultDate: Date)
    case edit(PlanTask)
}

struct TaskEditorSheet: View {
    let mode: EditorMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(SyncEngine.self) private var sync
    @Environment(TeamRoster.self) private var roster
    @Environment(SpacesRoster.self) private var spacesRoster
    @Environment(TagsRoster.self)   private var tagsRoster
    @Environment(AuthState.self)    private var auth
    @Environment(AppSettings.self)  private var settings

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var dateOnly: Date = .now
    @State private var time: Date = .now
    @State private var durationMinutes: Int = 30
    @State private var category: PlanCategory = .work
    @State private var status: PlanStatus = .open
    @State private var subtaskDrafts: [SubtaskDraft] = []
    @State private var newSubtaskText: String = ""
    @State private var whenPopoverOpen: Bool = false
    @State private var assigneeIds: Set<String> = []
    @State private var tagIds: Set<String> = []
    @State private var reminderMinutes: Int? = nil
    @State private var comments: [CommentDTO] = []
    @State private var newCommentText: String = ""
    @State private var loadingComments: Bool = false
    @FocusState private var focus: Field?

    fileprivate enum Field: Hashable { case title, note, newSubtask, subtask(UUID) }

    private let durationPresets: [Int] = [15, 30, 45, 60, 90, 120, 180, 240]

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFAF8F4).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        titleSection
                        whenSection
                        durationSection
                        reminderSection
                        categorySection
                        tagsSection
                        statusSection
                        assigneesSection
                        noteSection
                        subtasksSection
                        attachmentsSection
                        commentsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                }
                footer
            }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: load)
    }

    // MARK: – Header

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(category.color.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: isEdit ? "square.and.pencil" : "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(category.color)
                }
                Text(isEdit ? "Редактировать задачу" : "Новая задача")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VibePlanTheme.ink900)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VibePlanTheme.ink500)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.7), in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: – Title

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Название")
            TextField("", text: $title, prompt: Text("Что нужно сделать?").foregroundStyle(VibePlanTheme.ink400))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(VibePlanTheme.ink900)
                .focused($focus, equals: .title)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(focus == .title ? VibePlanTheme.ink900.opacity(0.4) : Color.black.opacity(0.06),
                                lineWidth: focus == .title ? 1.5 : 1)
                )
        }
    }

    // MARK: – When (date + time chip → popover)

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Когда")
            Button(action: { whenPopoverOpen.toggle() }) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VibePlanTheme.ink700)
                    Text(formattedDate)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VibePlanTheme.ink900)
                    Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1, height: 14)
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VibePlanTheme.ink700)
                    Text(formattedTime)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(VibePlanTheme.ink900)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VibePlanTheme.ink400)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $whenPopoverOpen, arrowEdge: .bottom) {
                whenPopoverContent
                    .padding(16)
                    .frame(width: 320)
            }
        }
    }

    private var whenPopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            DatePicker("", selection: $dateOnly, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ru_RU"))

            HStack {
                Text("Время")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(VibePlanTheme.ink500)
                Spacer()
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
        }
    }

    // MARK: – Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Длительность")
            HStack(spacing: 6) {
                ForEach(durationPresets, id: \.self) { mins in
                    Button(action: { durationMinutes = mins }) {
                        Text(durationLabel(mins))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(durationMinutes == mins ? .white : VibePlanTheme.ink700)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(durationMinutes == mins ? VibePlanTheme.ink900 : Color.white.opacity(0.7))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(durationMinutes == mins ? Color.clear : Color.black.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func durationLabel(_ mins: Int) -> String {
        if mins < 60 { return "\(mins) мин" }
        let h = Double(mins) / 60.0
        if h.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(h)) ч" }
        return String(format: "%.1f ч", h).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: – Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Категория")
            HStack(spacing: 6) {
                ForEach(PlanCategory.allCases) { cat in
                    Button(action: { category = cat }) {
                        HStack(spacing: 6) {
                            Circle().fill(cat.color).frame(width: 8, height: 8)
                            Text(cat.label)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(category == cat ? .white : VibePlanTheme.ink700)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(category == cat ? cat.color : cat.tintBackground)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(category == cat ? Color.clear : Color.black.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: – Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Статус")
            HStack(spacing: 6) {
                ForEach(PlanStatus.allCases) { st in
                    Button(action: { status = st }) {
                        HStack(spacing: 7) {
                            statusGlyph(for: st, selected: status == st)
                            Text(st.label)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(status == st ? .white : VibePlanTheme.ink700)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(status == st ? VibePlanTheme.ink900 : Color.white.opacity(0.7))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(status == st ? Color.clear : Color.black.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func statusGlyph(for st: PlanStatus, selected: Bool) -> some View {
        let strokeColor: Color = selected ? .white : VibePlanTheme.ink400
        switch st {
        case .open:
            Circle().strokeBorder(strokeColor, lineWidth: 1.5).frame(width: 12, height: 12)
        case .inProgress:
            ZStack {
                Circle().strokeBorder(strokeColor, lineWidth: 1.5).frame(width: 12, height: 12)
                Circle().trim(from: 0, to: 0.6).rotation(.degrees(-90))
                    .fill(selected ? .white : VibePlanTheme.catWork)
                    .frame(width: 8, height: 8)
            }
        case .done:
            ZStack {
                Circle().fill(selected ? .white : VibePlanTheme.ink900).frame(width: 12, height: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(selected ? VibePlanTheme.ink900 : .white)
            }
        }
    }

    // MARK: – Assignees

    /// In a space — pickable from that space's members.
    /// In personal scope — assignees are hidden (only you see your own tasks).
    private var availableAssignees: [TeamMemberDTO] {
        switch spacesRoster.scope {
        case .personal:
            return []
        case .space:
            return spacesRoster.currentSpaceMembers.map {
                TeamMemberDTO(id: $0.userId, email: $0.email, name: $0.name, role: $0.role)
            }
        }
    }

    @ViewBuilder
    private var assigneesSection: some View {
        if case .space = spacesRoster.scope {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    sectionLabel("Исполнители")
                    Spacer()
                    if !assigneeIds.isEmpty {
                        Text("\(assigneeIds.count) выбрано")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VibePlanTheme.ink400)
                    }
                }
                if availableAssignees.isEmpty {
                    Text("В пространстве пока только вы.")
                        .font(.system(size: 12))
                        .foregroundStyle(VibePlanTheme.ink500)
                        .padding(.vertical, 4)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(availableAssignees) { m in
                            Button(action: { toggleAssignee(m.id) }) {
                                HStack(spacing: 7) {
                                    AvatarBadge(name: m.name, email: m.email, size: 18, avatarPath: m.avatarUrl)
                                    Text(memberLabel(m))
                                        .font(.system(size: 12.5, weight: .medium))
                                    if assigneeIds.contains(m.id) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                }
                                .foregroundStyle(assigneeIds.contains(m.id) ? .white : VibePlanTheme.ink700)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(assigneeIds.contains(m.id) ? VibePlanTheme.ink900 : Color.white)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(assigneeIds.contains(m.id) ? Color.clear : Color.black.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func toggleAssignee(_ id: String) {
        if assigneeIds.contains(id) { assigneeIds.remove(id) } else { assigneeIds.insert(id) }
    }

    private func memberLabel(_ m: TeamMemberDTO) -> String {
        m.name.isEmpty ? m.email : m.name
    }

    // MARK: – Reminder

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Напомнить")
            HStack(spacing: 6) {
                ForEach([nil, 5, 15, 30, 60, 120, 24*60] as [Int?], id: \.self) { mins in
                    Button(action: { reminderMinutes = mins }) {
                        Text(reminderLabel(mins))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(reminderMinutes == mins ? .white : VibePlanTheme.ink700)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(reminderMinutes == mins ? VibePlanTheme.ink900 : Color.white)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(reminderMinutes == mins ? Color.clear : Color.black.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func reminderLabel(_ mins: Int?) -> String {
        guard let m = mins else { return "Не нужно" }
        if m < 60 { return "за \(m) мин" }
        if m == 60 { return "за час" }
        if m == 24 * 60 { return "за сутки" }
        return "за \(m / 60) ч"
    }

    // MARK: – Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("Метки")
                Spacer()
                Button(action: { Task { await createNewTag() } }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(VibePlanTheme.ink500)
                }
                .buttonStyle(.plain)
                .help("Создать новую метку")
            }
            if tagsRoster.tags.isEmpty {
                Text("Меток пока нет — добавь первую через «+»")
                    .font(.system(size: 12))
                    .foregroundStyle(VibePlanTheme.ink400)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(tagsRoster.tags) { tag in
                        Button(action: { toggleTag(tag.id) }) {
                            HStack(spacing: 5) {
                                Circle().fill(tagColor(tag).color).frame(width: 7, height: 7)
                                Text(tag.name)
                                    .font(.system(size: 12, weight: .medium))
                                if tagIds.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                            }
                            .foregroundStyle(tagIds.contains(tag.id) ? .white : VibePlanTheme.ink700)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(
                                Capsule().fill(tagIds.contains(tag.id)
                                               ? tagColor(tag).color
                                               : tagColor(tag).tintBackground)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func tagColor(_ tag: TagDTO) -> PlanCategory {
        PlanCategory(rawValue: tag.color) ?? .work
    }

    private func toggleTag(_ id: String) {
        if tagIds.contains(id) { tagIds.remove(id) } else { tagIds.insert(id) }
    }

    private func createNewTag() async {
        // Quick prompt via NSAlert — pragmatic for MVP
        let alert = NSAlert()
        alert.messageText = "Новая метка"
        alert.informativeText = "Введите название (короткое)"
        alert.alertStyle = .informational
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Создать")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            let scopeId: String? = {
                if case .space(let id) = spacesRoster.scope { return id }
                return nil
            }()
            let tag = try await client.createTag(name: name, color: category.rawValue, spaceId: scopeId)
            tagsRoster.upsert(tag)
            tagIds.insert(tag.id)
        } catch {
            print("[create tag] \(error)")
        }
    }

    // MARK: – Comments

    @ViewBuilder
    private var commentsSection: some View {
        if case .edit(let task) = mode {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionLabel("Комментарии")
                    Spacer()
                    if loadingComments { ProgressView().controlSize(.small) }
                    if !comments.isEmpty {
                        Text("\(comments.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VibePlanTheme.ink400)
                    }
                }
                VStack(spacing: 6) {
                    ForEach(comments) { c in
                        CommentRow(comment: c, onDelete: { Task { await deleteComment(c) } })
                    }
                    HStack(alignment: .top, spacing: 8) {
                        TextField("", text: $newCommentText,
                                  prompt: Text("Написать комментарий…").foregroundStyle(VibePlanTheme.ink400),
                                  axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(VibePlanTheme.ink900)
                            .lineLimit(1...5)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.08)))
                        Button(action: { Task { await postComment(taskId: task.serverId) } }) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(VibePlanTheme.ink900, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty || task.serverId == nil)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    private func loadComments(taskId: String?) async {
        guard let tid = taskId else { return }
        loadingComments = true; defer { loadingComments = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            comments = try await client.listComments(taskId: tid)
        } catch {
            print("[comments load] \(error)")
        }
    }

    private func postComment(taskId: String?) async {
        guard let tid = taskId else { return }
        let body = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            let c = try await client.addComment(taskId: tid, body: body)
            comments.append(c)
            newCommentText = ""
        } catch {
            print("[comment add] \(error)")
        }
    }

    private func deleteComment(_ c: CommentDTO) async {
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            try await client.deleteComment(id: c.id)
            comments.removeAll { $0.id == c.id }
        } catch {
            print("[comment delete] \(error)")
        }
    }

    // MARK: – Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Заметка")
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Контекст, ссылки, мысли…")
                        .font(.system(size: 13))
                        .foregroundStyle(VibePlanTheme.ink400)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note)
                    .font(.system(size: 13))
                    .foregroundStyle(VibePlanTheme.ink900)
                    .focused($focus, equals: .note)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 86)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(focus == .note ? VibePlanTheme.ink900.opacity(0.4) : Color.black.opacity(0.06))
            )
        }
    }

    // MARK: – Subtasks

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("Подзадачи")
                Spacer()
                if !subtaskDrafts.isEmpty {
                    Text("\(subtaskDrafts.filter(\.done).count) / \(subtaskDrafts.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(VibePlanTheme.ink400)
                }
            }
            VStack(spacing: 4) {
                ForEach($subtaskDrafts) { $draft in
                    SubtaskRow(
                        draft: $draft,
                        focus: $focus,
                        onDelete: { subtaskDrafts.removeAll { $0.id == draft.id } }
                    )
                }
                addSubtaskRow
            }
        }
    }

    private var addSubtaskRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VibePlanTheme.ink400)
                .frame(width: 18, height: 18)

            TextField("", text: $newSubtaskText,
                      prompt: Text("Добавить подзадачу").foregroundStyle(VibePlanTheme.ink400))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(VibePlanTheme.ink900)
                .focused($focus, equals: .newSubtask)
                .onSubmit(addSubtask)

            if !newSubtaskText.isEmpty {
                Button("Добавить", action: addSubtask)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(VibePlanTheme.ink900, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.black.opacity(0.10))
        )
    }

    // MARK: – Footer

    private var footer: some View {
        HStack {
            if isEdit {
                Button(action: deleteAndClose) {
                    Label("Удалить", systemImage: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("Отмена", action: { dismiss() })
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(VibePlanTheme.ink900)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.white.opacity(0.7), in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.08)))

            Button(action: save) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text(isEdit ? "Сохранить" : "Создать")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(VibePlanTheme.ink900, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.white.opacity(0.5))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: – Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(VibePlanTheme.ink500)
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: dateOnly)
    }

    private var formattedTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: time)
    }

    // MARK: – Actions

    private func addSubtask() {
        let s = newSubtaskText.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        subtaskDrafts.append(SubtaskDraft(title: s, done: false))
        newSubtaskText = ""
        focus = .newSubtask
    }

    private func load() {
        switch mode {
        case .add(let defaultDate):
            let cal = CalendarUtil.ru
            dateOnly = defaultDate
            let now = Date()
            var comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
            comps.minute = (cal.component(.minute, from: now) < 30) ? 30 : 0
            if comps.minute == 0 { comps.hour = (comps.hour ?? 0) + 1 }
            time = cal.date(from: comps) ?? now

            if !CalendarUtil.isSameDay(defaultDate, .now) {
                var pin = cal.dateComponents([.year, .month, .day], from: defaultDate)
                pin.hour = 9
                pin.minute = 0
                time = cal.date(from: pin) ?? defaultDate
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus = .title }

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
            assigneeIds = Set(task.assignees.map(\.userId))
            tagIds = Set(task.tagIds)
            reminderMinutes = task.reminderMinutes
            Task { await loadComments(taskId: task.serverId) }
        }
    }

    private func save() {
        let merged = mergeDateAndTime()
        switch mode {
        case .add:
            // New tasks inherit the current scope: personal → spaceServerId nil,
            // a space scope → that space's id.
            let inheritedSpaceId: String? = {
                if case .space(let id) = spacesRoster.scope { return id }
                return nil
            }()
            let task = PlanTask(
                title: title,
                note: note,
                startDate: merged,
                durationMinutes: durationMinutes,
                category: category,
                status: status,
                spaceServerId: inheritedSpaceId
            )
            task.subtasks = subtaskDrafts.enumerated().map { idx, d in
                Subtask(title: d.title, done: d.done, order: idx)
            }
            task.assignees = assignees(for: assigneeIds)
            task.tagIds = Array(tagIds)
            task.reminderMinutes = reminderMinutes
            ctx.insert(task)
            try? ctx.save()
            sync.pushCreate(task)

        case .edit(let task):
            task.title = title
            task.note = note
            task.startDate = merged
            task.durationMinutes = durationMinutes
            task.category = category
            task.status = status
            for s in task.subtasks { ctx.delete(s) }
            task.subtasks = subtaskDrafts.enumerated().map { idx, d in
                Subtask(title: d.title, done: d.done, order: idx)
            }
            task.assignees = assignees(for: assigneeIds)
            task.tagIds = Array(tagIds)
            task.reminderMinutes = reminderMinutes
            try? ctx.save()
            sync.pushUpdate(task)
            ReminderScheduler.rescheduleAll(in: ctx.container)
        }
        dismiss()
    }

    private func deleteAndClose() {
        if case .edit(let task) = mode {
            let sid = task.serverId
            ctx.delete(task)
            try? ctx.save()
            sync.pushDelete(serverId: sid)
        }
        dismiss()
    }

    // MARK: – Attachments

    @ViewBuilder
    private var attachmentsSection: some View {
        if case .edit(let task) = mode {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionLabel("Файлы")
                    Spacer()
                    if !task.attachments.isEmpty {
                        Text("\(task.attachments.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VibePlanTheme.ink400)
                    }
                }
                VStack(spacing: 6) {
                    ForEach(task.attachments.sorted(by: { $0.uploadedAt < $1.uploadedAt })) { att in
                        AttachmentRow(att: att, onDelete: { Task { await deleteAttachment(att) } })
                    }
                    Button(action: pickAndUploadAttachment) {
                        HStack(spacing: 8) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VibePlanTheme.ink500)
                            Text("Добавить файл")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(VibePlanTheme.ink700)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .foregroundStyle(Color.black.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            // For new tasks, attachments are added after first save.
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Файлы")
                Text("Сохрани задачу — потом сможешь прикрепить файлы.")
                    .font(.system(size: 12))
                    .foregroundStyle(VibePlanTheme.ink400)
            }
        }
    }

    private func pickAndUploadAttachment() {
        guard case .edit(let task) = mode, let serverId = task.serverId else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let mime = mimeType(for: url)
                let client = APIClient(baseURL: settings.backendURL, token: auth.token)
                let dto = try await client.uploadAttachment(taskId: serverId, fileURL: url, mimeType: mime)
                let local = TaskAttachment(
                    serverId: dto.id, filename: dto.filename, mimeType: dto.mimeType,
                    sizeBytes: dto.sizeBytes, url: dto.url,
                    uploadedAt: dto.uploadedAt, uploadedById: dto.uploadedById
                )
                task.attachments.append(local)
                try? ctx.save()
            } catch {
                print("[attachment upload] \(error)")
            }
        }
    }

    private func deleteAttachment(_ att: TaskAttachment) async {
        guard case .edit(let task) = mode else { return }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            try await client.deleteAttachment(id: att.serverId)
            task.attachments.removeAll { $0.serverId == att.serverId }
            ctx.delete(att)
            try? ctx.save()
        } catch {
            print("[attachment delete] \(error)")
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":  return "application/pdf"
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":  return "image/gif"
        case "webp": return "image/webp"
        case "doc":  return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":  return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt":  return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt":  return "text/plain"
        case "md":   return "text/markdown"
        case "zip":  return "application/zip"
        case "mp3":  return "audio/mpeg"
        case "mp4":  return "video/mp4"
        case "mov":  return "video/quicktime"
        default:     return "application/octet-stream"
        }
    }

    private func assignees(for ids: Set<String>) -> [TaskAssignee] {
        ids.compactMap { id -> TaskAssignee? in
            if let m = spacesRoster.currentSpaceMembers.first(where: { $0.userId == id }) {
                return TaskAssignee(userId: m.userId, email: m.email, name: m.name)
            }
            if let m = roster.member(byId: id) {
                return TaskAssignee(userId: m.id, email: m.email, name: m.name)
            }
            return nil
        }
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

private struct SubtaskRow: View {
    @Binding var draft: SubtaskDraft
    var focus: FocusState<TaskEditorSheet.Field?>.Binding
    let onDelete: () -> Void

    @State private var hovered: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { draft.done.toggle() }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(draft.done ? VibePlanTheme.ink900 : VibePlanTheme.ink300, lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(draft.done ? VibePlanTheme.ink900 : Color.clear)
                        )
                        .frame(width: 16, height: 16)
                    if draft.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            TextField("", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(draft.done ? VibePlanTheme.ink400 : VibePlanTheme.ink900)
                .strikethrough(draft.done, color: VibePlanTheme.ink400)
                .focused(focus, equals: .subtask(draft.id))

            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VibePlanTheme.ink400)
                        .frame(width: 18, height: 18)
                        .background(.white.opacity(0.8), in: Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(hovered ? 0.85 : 0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        )
        .onHover { hovered = $0 }
    }
}

private struct SubtaskDraft: Identifiable {
    let id = UUID()
    var title: String
    var done: Bool
}

private struct CommentRow: View {
    let comment: CommentDTO
    let onDelete: () -> Void

    @Environment(AuthState.self)    private var auth
    @Environment(TeamRoster.self)   private var roster
    @Environment(SpacesRoster.self) private var spacesRoster
    @State private var hovered: Bool = false

    private var authorInfo: (name: String, email: String, avatarPath: String?)? {
        guard let id = comment.authorId else { return nil }
        if let m = roster.member(byId: id) { return (m.name, m.email, m.avatarUrl) }
        for s in spacesRoster.spaces {
            if let m = s.members.first(where: { $0.userId == id }) {
                return (m.name, m.email, m.avatarUrl)
            }
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarBadge(name: authorInfo?.name ?? "",
                        email: authorInfo?.email ?? "",
                        size: 26, avatarPath: authorInfo?.avatarPath)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(authorInfo?.name.isEmpty == false
                         ? authorInfo!.name
                         : (authorInfo?.email ?? "—"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VibePlanTheme.ink900)
                    Text(timeString)
                        .font(.system(size: 11))
                        .foregroundStyle(VibePlanTheme.ink400)
                    Spacer()
                    if hovered, comment.authorId == auth.user?.id {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(comment.body)
                    .font(.system(size: 13))
                    .foregroundStyle(VibePlanTheme.ink800OrInk900)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.06)))
        .onHover { hovered = $0 }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: comment.createdAt)
    }
}

private extension VibePlanTheme {
    static var ink800OrInk900: Color { ink900 }
}

private struct AttachmentRow: View {
    let att: TaskAttachment
    let onDelete: () -> Void

    @Environment(AppSettings.self) private var settings
    @State private var hovered: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconBg)
                    .frame(width: 30, height: 30)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconFg)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(att.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VibePlanTheme.ink900)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sizeString)
                    .font(.system(size: 11))
                    .foregroundStyle(VibePlanTheme.ink500)
            }
            Spacer()
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
                        .padding(6)
                        .background(Color.red.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Удалить файл")
            }
            Button(action: openFile) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(VibePlanTheme.ink500)
            }
            .buttonStyle(.plain)
            .help("Открыть")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.06)))
        .onHover { hovered = $0 }
    }

    private var iconName: String {
        if att.mimeType.hasPrefix("image/") { return "photo" }
        if att.mimeType == "application/pdf" { return "doc.richtext" }
        if att.mimeType.contains("word") || att.mimeType.contains("text") { return "doc.text" }
        if att.mimeType.contains("sheet") || att.mimeType.contains("excel") { return "tablecells" }
        if att.mimeType.contains("presentation") || att.mimeType.contains("powerpoint") { return "rectangle.stack" }
        if att.mimeType == "application/zip" { return "doc.zipper" }
        if att.mimeType.hasPrefix("audio/") { return "waveform" }
        if att.mimeType.hasPrefix("video/") { return "play.rectangle" }
        return "doc"
    }

    private var iconBg: Color {
        if att.mimeType.hasPrefix("image/") { return VibePlanTheme.catLearning.opacity(0.15) }
        if att.mimeType == "application/pdf" { return VibePlanTheme.catUrgent.opacity(0.15) }
        if att.mimeType.contains("sheet") { return VibePlanTheme.catLearning.opacity(0.15) }
        if att.mimeType.contains("word") { return VibePlanTheme.catWork.opacity(0.15) }
        return VibePlanTheme.ink100
    }

    private var iconFg: Color {
        if att.mimeType.hasPrefix("image/") { return VibePlanTheme.catLearning }
        if att.mimeType == "application/pdf" { return VibePlanTheme.catUrgent }
        if att.mimeType.contains("sheet") { return VibePlanTheme.catLearning }
        if att.mimeType.contains("word") { return VibePlanTheme.catWork }
        return VibePlanTheme.ink500
    }

    private var sizeString: String {
        let bytes = att.sizeBytes
        if bytes < 1024 { return "\(bytes) Б" }
        if bytes < 1024 * 1024 { return String(format: "%.1f КБ", Double(bytes) / 1024) }
        return String(format: "%.1f МБ", Double(bytes) / 1024 / 1024)
    }

    private func openFile() {
        guard let url = URL(string: att.url, relativeTo: settings.backendURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
