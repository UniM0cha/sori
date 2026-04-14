import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayWindowController {
    private var window: NSPanel?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let host = NSHostingView(rootView: RecordingOverlayView(appState: appState))
            host.frame = NSRect(x: 0, y: 0, width: 260, height: 60)
            panel.contentView = host
            self.window = panel
        }
        positionPanel()
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func positionPanel() {
        guard let window, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let w = window.frame.size.width
        let x = frame.origin.x + (frame.size.width - w) / 2
        let y = frame.origin.y + 80
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var appState: AppState

    private let barCount = 10

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(appState.isBlinkOn ? 1.0 : 0.3)

            Text(timerString)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 44, alignment: .leading)

            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 3, height: barHeight(for: index))
                }
            }
            .frame(height: 28)

            Text(statusLabel)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.72))
        )
        .frame(width: 260, height: 60)
    }

    private var timerString: String {
        let total = Int(appState.recordingElapsed)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var statusLabel: String {
        switch appState.recordingState {
        case .recording: return "녹음 중"
        case .transcribing: return "전사 중"
        default: return ""
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(min(max(appState.currentInputLevel * 2.5, 0), 1))
        let phase = CGFloat(index) / CGFloat(barCount - 1)
        let wave = sin((phase + level) * .pi)
        let normalized = max(0.15, wave * level)
        return 4 + normalized * 22
    }
}
