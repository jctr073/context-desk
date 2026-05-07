import SwiftUI

@main
struct ContextDeskApp: App {
    var body: some Scene {
        WindowGroup("ContextDesk") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
