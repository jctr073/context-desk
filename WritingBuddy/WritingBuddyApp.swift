import SwiftUI

@main
struct WritingBuddyApp: App {
    var body: some Scene {
        WindowGroup("WritingBuddy") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
