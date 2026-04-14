import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self(
        "toggleRecording",
        default: .init(.space, modifiers: [.option])
    )
}

@MainActor
final class HotkeyManager {
    private weak var appState: AppState?
    private var escMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak appState] in
            guard let appState else { return }
            Task { @MainActor in appState.toggleRecording() }
        }
        installEscMonitor()
    }

    private func installEscMonitor() {
        if escMonitor != nil { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }  // kVK_Escape
            guard let appState = self?.appState else { return }
            if appState.isRecordingOrTranscribing {
                Task { @MainActor in appState.cancelRecording() }
            }
        }
    }
}
