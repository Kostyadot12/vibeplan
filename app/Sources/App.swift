import SwiftUI
import SwiftData

@main
struct VibePlanApp: App {
    let container: ModelContainer

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
    }

    var body: some Scene {
        WindowGroup("VibePlan") {
            MainWindowView()
                .frame(minWidth: 1100, minHeight: 720)
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
