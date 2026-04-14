import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState: AppState
    let permissions = PermissionChecker()
    private var hotkeyManager: HotkeyManager?
    private var welcomeController: WelcomeWindowController?

    override init() {
        UserDefaults.registerSoriDefaults()
        self.appState = AppState()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { [weak self] in
            guard let self else { return }
            await self.appState.bootstrap()
            self.presentInitialUI()
        }
    }

    private func presentInitialUI() {
        let hasCompleted = UserDefaults.standard.bool(forKey: PreferenceKeys.hasCompletedWelcome)
        let needsWelcome = !hasCompleted || !appState.modelCached || !permissions.bothGranted

        if needsWelcome {
            showWelcome()
        } else {
            startRegularSession()
        }
    }

    private func showWelcome() {
        let controller = WelcomeWindowController(appState: appState, permissions: permissions)
        welcomeController = controller
        controller.show { [weak self] in
            guard let self else { return }
            self.welcomeController = nil
            self.startRegularSession()
        }
    }

    private func startRegularSession() {
        if hotkeyManager == nil {
            let hotkey = HotkeyManager(appState: appState)
            hotkey.start()
            self.hotkeyManager = hotkey
        }
    }
}
