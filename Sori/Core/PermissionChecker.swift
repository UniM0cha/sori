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
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
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
        // Equivalent to kAXTrustedCheckOptionPrompt, but hard-coded to avoid Swift 6
        // concurrency warnings about accessing a global `var` from the ApplicationServices header.
        let options: CFDictionary = ["AXTrustedCheckOptionPrompt": false] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }
}
