import SwiftUI

@main
struct VibePlanApp: App {
    var body: some Scene {
        WindowGroup("VibePlan") {
            MainWindowView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
