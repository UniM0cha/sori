import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState: AppState
    private var hotkeyManager: HotkeyManager?

    override init() {
        UserDefaults.registerSoriDefaults()
        self.appState = AppState()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hotkey = HotkeyManager(appState: appState)
        hotkey.start()
        self.hotkeyManager = hotkey

        Task { [weak self] in
            await self?.appState.bootstrap()
        }
    }
}
