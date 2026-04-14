import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?
    private let appState: AppState
    private let permissions: PermissionChecker
    private var onFinish: (@MainActor () -> Void)?

    init(appState: AppState, permissions: PermissionChecker) {
        self.appState = appState
        self.permissions = permissions
    }

    func show(onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish

        if window == nil {
            let view = WelcomeView(
                permissions: permissions,
                appState: appState,
                onFinish: { [weak self] in
                    self?.finishAndClose()
                }
            )
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sori"
            window.center()
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishAndClose() {
        window?.close()
        onFinish?()
        onFinish = nil
    }
}

struct WelcomeView: View {
    @ObservedObject var permissions: PermissionChecker
    @ObservedObject var appState: AppState
    var onFinish: () -> Void

    @State private var isDownloading = false
    @State private var downloadErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            MicrophoneRow(permissions: permissions)
            AccessibilityRow(permissions: permissions)
            ModelRow(
                appState: appState,
                permissions: permissions,
                isDownloading: $isDownloading,
                errorMessage: $downloadErrorMessage
            )
            Spacer(minLength: 8)
            footer
        }
        .padding(24)
        .frame(width: 540, height: 520)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // When the user returns from System Settings after flipping the toggle,
            // recheck immediately instead of waiting for the next polling tick.
            permissions.refreshNow()
        }
    }

    private var canStart: Bool {
        permissions.microphoneGranted && permissions.accessibilityGranted && appState.modelCached
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sori에 오신 것을 환영합니다")
                .font(.largeTitle.bold())
            Text("받아쓰기 앱을 사용하려면 아래 세 단계를 완료해 주세요.")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("건너뛰기") {
                onFinish()
            }
            Spacer()
            Button("시작") {
                UserDefaults.standard.set(true, forKey: PreferenceKeys.hasCompletedWelcome)
                onFinish()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canStart)
        }
    }
}

private struct MicrophoneRow: View {
    @ObservedObject var permissions: PermissionChecker

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permissions.microphoneGranted ? "checkmark.circle.fill" : "mic.fill")
                .foregroundStyle(permissions.microphoneGranted ? Color.green : Color.orange)
                .font(.title2)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("1. 마이크").font(.headline)
                Text("음성을 녹음하는 데 필요합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !permissions.microphoneGranted {
                Button("허용하기") {
                    Task { await permissions.requestMicrophone() }
                }
            }
        }
    }
}

private struct AccessibilityRow: View {
    @ObservedObject var permissions: PermissionChecker

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permissions.accessibilityGranted ? "checkmark.circle.fill" : "hand.raised.fill")
                .foregroundStyle(permissions.accessibilityGranted ? Color.green : Color.orange)
                .font(.title2)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("2. 손쉬운 사용").font(.headline)
                Text("전사한 텍스트를 활성 앱에 붙여넣는 데 필요합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("설정에서 Sori를 추가하면 자동으로 감지됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !permissions.accessibilityGranted {
                Button("시스템 설정 열기") {
                    permissions.openAccessibilitySettings()
                }
            }
        }
    }
}

private struct ModelRow: View {
    @ObservedObject var appState: AppState
    @ObservedObject var permissions: PermissionChecker
    @Binding var isDownloading: Bool
    @Binding var errorMessage: String?

    private var modelId: String {
        PreferencesSnapshot().modelId
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            details
            Spacer()
            if !appState.modelCached && !isDownloading {
                Button("다운로드 시작") {
                    Task { await startDownload() }
                }
                .disabled(!permissions.bothGranted)
            }
        }
    }

    private var icon: some View {
        Image(systemName: appState.modelCached ? "checkmark.circle.fill" : "arrow.down.circle.fill")
            .foregroundStyle(appState.modelCached ? Color.green : Color.blue)
            .font(.title2)
            .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("3. 모델 다운로드").font(.headline)
            Text(modelId)
                .font(.caption2)
                .foregroundStyle(.secondary)
            statusLine
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if isDownloading {
            ProgressView(value: appState.downloadProgress)
                .frame(maxWidth: 240)
            Text("\(Int(appState.downloadProgress * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if appState.modelCached {
            Text("다운로드 완료")
                .font(.caption)
                .foregroundStyle(.green)
        } else if let msg = errorMessage {
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text("bf16 모델은 약 3.4 GB입니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func startDownload() async {
        isDownloading = true
        errorMessage = nil
        await appState.downloadModel()
        if !appState.modelCached {
            if case .error(let msg) = appState.recordingState {
                errorMessage = msg
            }
        }
        isDownloading = false
    }
}
