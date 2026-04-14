import AppKit
import ApplicationServices
import AVFoundation
import Combine

@MainActor
final class PermissionChecker: ObservableObject {
    @Published private(set) var microphoneGranted: Bool = false
    @Published private(set) var accessibilityGranted: Bool = false

    private var timer: Timer?

    init() {
        refresh()
    }

    func startPolling() {
        refresh()
        timer?.invalidate()
        // Register on .common so ticks keep firing during SwiftUI event tracking
        // (e.g. while the Welcome window is being interacted with or a sheet is up).
        let newTimer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Force an immediate recheck. Call this from UI code when the window comes
    /// back to the foreground (e.g. after the user toggled access in System Settings).
    func refreshNow() {
        refresh()
    }

    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var bothGranted: Bool {
        microphoneGranted && accessibilityGranted
    }

    private func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        // Passing nil is equivalent to {kAXTrustedCheckOptionPrompt: false} and avoids
        // the Swift 6 concurrency warning about reading the global ApplicationServices var.
        accessibilityGranted = AXIsProcessTrustedWithOptions(nil)
    }
}
