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
    @State private var settingsOpen: Bool = false
    @State private var searchQuery: String = ""
    @State private var spaceSheetMode: SpaceSheetMode?

    var body: some View {
        ZStack {
            VibePlanTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ToolbarBar(
                    search: $searchQuery,
                    onToday: goToToday,
                    onAdd: { addingForDate = selectedDate },
                    onSettings: { settingsOpen = true },
                    onCreateSpace: { spaceSheetMode = .create },
                    onManageSpace: { id in spaceSheetMode = .manage(spaceId: id) }
                )
                Divider().opacity(0.4)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        MonthGridView(
                            monthAnchor: $monthAnchor,
                            selectedDate: $selectedDate,
                            searchQuery: searchQuery
                        )
                        .frame(maxHeight: .infinity)

                        InboxBar(expanded: $inboxExpanded,
                                 searchQuery: searchQuery,
                                 onEdit: { editingTask = $0 })
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                    }
                    .frame(minWidth: 700)

                    Divider().opacity(0.4)

                    DayPanelView(
                        date: selectedDate,
                        searchQuery: searchQuery,
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
        .sheet(isPresented: $settingsOpen) {
            SettingsSheet().frame(minWidth: 520, minHeight: 480)
        }
        .sheet(item: $spaceSheetMode) { mode in
            SpaceSheet(mode: mode).frame(minWidth: 520, minHeight: 560)
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
    @Binding var search: String
    let onToday: () -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void
    let onCreateSpace: () -> Void
    let onManageSpace: (String) -> Void

    @Environment(AuthState.self)      private var auth
    @Environment(SyncEngine.self)     private var sync
    @Environment(RealtimeClient.self) private var realtime
    @Environment(SpacesRoster.self)   private var spacesRoster

    var body: some View {
        HStack(spacing: 12) {
            scopePicker

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VibePlanTheme.ink400)
                TextField("", text: $search,
                          prompt: Text("Поиск…").foregroundStyle(VibePlanTheme.ink400))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(VibePlanTheme.ink900)
                if !search.isEmpty {
                    Button(action: { search = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VibePlanTheme.ink400)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .frame(maxWidth: 320)
            .background(.white.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.06)))

            Spacer()

            syncStatusChip

            Button(action: onToday) {
                Label("Сегодня", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VibePlanTheme.ink900)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.85), in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.08)))
            .keyboardShortcut("t", modifiers: [.command])

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
            .keyboardShortcut("n", modifiers: [.command])

            Button(action: onSettings) {
                UserBadge(user: auth.user, size: 30)
            }
            .buttonStyle(.plain)
            .help("Настройки")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var syncStatusChip: some View {
        HStack(spacing: 6) {
            if sync.isSyncing {
                ProgressView().controlSize(.small)
                Text("Синк…").font(.system(size: 11)).foregroundStyle(VibePlanTheme.ink500)
            } else if sync.lastError != nil {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text("Ошибка").font(.system(size: 11)).foregroundStyle(.red)
            }
            switch realtime.status {
            case .live:        liveDot(color: .green,            label: "Live")
            case .connecting:  liveDot(color: .orange,           label: "Подключ.")
            case .offline:     liveDot(color: VibePlanTheme.ink300, label: "Offline")
            }
        }
    }

    private func liveDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11)).foregroundStyle(VibePlanTheme.ink500)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.white.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.05)))
    }

    private var scopePicker: some View {
        Menu {
            Button(action: { spacesRoster.scope = .personal }) {
                Label("Личные", systemImage: "person.fill")
            }
            if !spacesRoster.spaces.isEmpty {
                Divider()
                ForEach(spacesRoster.spaces) { s in
                    Button(action: { spacesRoster.scope = .space(s.id) }) {
                        Label(s.name, systemImage: "folder.fill")
                    }
                }
            }
            Divider()
            Button(action: onCreateSpace) {
                Label("Создать пространство…", systemImage: "plus.circle")
            }
            if case .space(let id) = spacesRoster.scope, spacesRoster.space(byId: id) != nil {
                Button(action: { onManageSpace(id) }) {
                    Label("Настроить пространство…", systemImage: "gearshape")
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: scopeIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(scopeIconColor)
                Text(scopeTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VibePlanTheme.ink900)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(VibePlanTheme.ink400)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.08)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var scopeTitle: String {
        switch spacesRoster.scope {
        case .personal: return "Личные"
        case .space(let id):
            if let s = spacesRoster.space(byId: id) { return s.name }
            return "Пространство"
        }
    }

    private var scopeIcon: String {
        switch spacesRoster.scope {
        case .personal: return "person.fill"
        case .space:    return "folder.fill"
        }
    }

    private var scopeIconColor: Color {
        switch spacesRoster.scope {
        case .personal: return VibePlanTheme.ink700
        case .space(let id):
            if let s = spacesRoster.space(byId: id),
               let cat = PlanCategory(rawValue: s.color) {
                return cat.color
            }
            return VibePlanTheme.ink700
        }
    }
}

extension SpaceSheetMode: Identifiable {
    var id: String {
        switch self {
        case .create: return "__create__"
        case .manage(let id): return "manage:\(id)"
        }
    }
}
