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
    @State private var tagsRoster: TagsRoster
    @State private var activityFeed: ActivityFeed
    @State private var updateChecker: UpdateChecker
    @State private var updater: Updater

    init() {
        do {
            container = try ModelContainer(
                for: PlanTask.self, Subtask.self, TaskAssignee.self,
                    TaskAttachment.self, TaskComment.self,
                    Space.self, SpaceMember.self
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
        let tg   = TagsRoster(auth: auth, settings: settings)
        let af   = ActivityFeed(auth: auth, settings: settings)
        let uc   = UpdateChecker()
        let up   = Updater()
        _auth          = State(initialValue: auth)
        _settings      = State(initialValue: settings)
        _sync          = State(initialValue: sync)
        _realtime      = State(initialValue: rt)
        _roster        = State(initialValue: rost)
        _spacesRoster  = State(initialValue: sp)
        _tagsRoster    = State(initialValue: tg)
        _activityFeed  = State(initialValue: af)
        _updateChecker = State(initialValue: uc)
        _updater       = State(initialValue: up)
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
                .environment(tagsRoster)
                .environment(activityFeed)
                .environment(updateChecker)
                .environment(updater)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.light)   // user chose «только светлая» — force it
                .tint(VibePlanTheme.ink900)
                .task { @MainActor in
                    realtime.spacesRoster = spacesRoster
                    realtime.tagsRoster   = tagsRoster
                    await Notifier.requestAuthorizationIfNeeded()
                    updateChecker.startPolling()
                    if auth.isAuthenticated {
                        spacesRoster.restoreScope()
                        await sync.fullSync()
                        await roster.refresh()
                        await spacesRoster.refresh()
                        await tagsRoster.refresh(scope: spacesRoster.scope)
                        realtime.start()
                        ReminderScheduler.rescheduleAll(in: container)
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
    @Environment(AuthState.self)       private var auth
    @Environment(SyncEngine.self)      private var sync
    @Environment(RealtimeClient.self)  private var realtime
    @Environment(TeamRoster.self)      private var roster
    @Environment(SpacesRoster.self)    private var spacesRoster
    @Environment(UpdateChecker.self)   private var updateChecker

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainWindowView()
            } else {
                LoginView()
            }
        }
        // Mandatory update sheet — sits above EVERYTHING (auth or main UI)
        // and cannot be dismissed. Only path forward is to install or ⌘Q.
        .sheet(item: Binding(
            get: { updateChecker.available },
            set: { _ in /* read-only — checker drives this */ }
        )) { release in
            UpdateSheet(release: release)
                .frame(minWidth: 540, minHeight: 540)
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
