import SwiftUI
import SwiftData

@main
struct VibePlanApp: App {
    let container: ModelContainer
    @State private var auth: AuthState
    @State private var settings: AppSettings
    @State private var sync: SyncEngine

    init() {
        do {
            container = try ModelContainer(for: PlanTask.self, Subtask.self)
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
        _auth     = State(initialValue: auth)
        _settings = State(initialValue: settings)
        _sync     = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup("VibePlan") {
            RootView()
                .environment(auth)
                .environment(settings)
                .environment(sync)
                .frame(minWidth: 1100, minHeight: 720)
                .task {
                    // If we already have a token from Keychain, kick off a full
                    // reconciliation so the calendar shows live team data.
                    if auth.isAuthenticated {
                        await sync.fullSync()
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
    @Environment(AuthState.self)  private var auth
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainWindowView()
            } else {
                LoginView()
            }
        }
        .onChange(of: auth.isAuthenticated) { _, nowAuthed in
            // First successful login → pull team data
            if nowAuthed {
                Task { await sync.fullSync() }
            }
        }
    }
}
