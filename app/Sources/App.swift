import SwiftUI
import SwiftData

@main
struct VibePlanApp: App {
    let container: ModelContainer
    @State private var auth: AuthState
    @State private var settings: AppSettings
    @State private var sync: SyncEngine
    @State private var realtime: RealtimeClient
    @State private var roster: TeamRoster
    @State private var spacesRoster: SpacesRoster

    init() {
        do {
            container = try ModelContainer(
                for: PlanTask.self, Subtask.self, TaskAssignee.self, Space.self, SpaceMember.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Seed once if the store is empty (first launch).
        let ctx = container.mainContext
        let descriptor = FetchDescriptor<PlanTask>()
        let count = (try? ctx.fetchCount(descriptor)) ?? 0
        if count == 0 {
            Seed.populate(into: ctx)
        }

        let auth = AuthState()
        let settings = AppSettings()
        let sync = SyncEngine(auth: auth, settings: settings, container: container)
        let rt   = RealtimeClient(auth: auth, settings: settings, container: container)
        let rost = TeamRoster(auth: auth, settings: settings)
        let sp   = SpacesRoster(auth: auth, settings: settings)
        _auth         = State(initialValue: auth)
        _settings     = State(initialValue: settings)
        _sync         = State(initialValue: sync)
        _realtime     = State(initialValue: rt)
        _roster       = State(initialValue: rost)
        _spacesRoster = State(initialValue: sp)
    }

    var body: some Scene {
        WindowGroup("VibePlan") {
            RootView()
                .environment(auth)
                .environment(settings)
                .environment(sync)
                .environment(realtime)
                .environment(roster)
                .environment(spacesRoster)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.light)   // user chose «только светлая» — force it
                .tint(VibePlanTheme.ink900)
                .task { @MainActor in
                    realtime.spacesRoster = spacesRoster
                    if auth.isAuthenticated {
                        spacesRoster.restoreScope()
                        await sync.fullSync()
                        await roster.refresh()
                        await spacesRoster.refresh()
                        realtime.start()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1320, height: 820)
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Routes between login screen and the main calendar based on auth state.
private struct RootView: View {
    @Environment(AuthState.self)      private var auth
    @Environment(SyncEngine.self)     private var sync
    @Environment(RealtimeClient.self) private var realtime
    @Environment(TeamRoster.self)     private var roster
    @Environment(SpacesRoster.self)   private var spacesRoster

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainWindowView()
            } else {
                LoginView()
            }
        }
        .onChange(of: auth.isAuthenticated) { _, nowAuthed in
            if nowAuthed {
                Task { @MainActor in
                    spacesRoster.restoreScope()
                    await sync.fullSync()
                    await roster.refresh()
                    await spacesRoster.refresh()
                    realtime.start()
                }
            } else {
                realtime.stop()
            }
        }
    }
}
