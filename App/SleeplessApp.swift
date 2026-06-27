import SwiftUI

@main
struct SleeplessApp: App {
    var body: some Scene {
        MenuBarExtra("Sleepless", systemImage: "cup.and.saucer") {
            Text("Sleepless 0.1.0")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
