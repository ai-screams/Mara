import SwiftUI
import MaraCore

@main
struct MaraApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(session: env.session, prefs: env.prefs)
        } label: {
            Image(systemName: env.session.state.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuBarExtraStyle(.menu)
        Settings {
            SettingsView(prefs: env.prefs)
        }
    }
}
