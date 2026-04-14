import SwiftUI

@main
struct SoriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(appState: appDelegate.appState, history: appDelegate.appState.history)
        } label: {
            Image(systemName: appDelegate.appState.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
