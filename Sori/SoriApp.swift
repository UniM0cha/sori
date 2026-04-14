import SwiftUI

@main
struct SoriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(appState: appDelegate.appState)
        } label: {
            Image(systemName: appDelegate.appState.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: appState.menuBarSymbolName)
                Text(appState.statusLabel)
                    .font(.headline)
            }
            Divider()
            if !appState.modelCached {
                Text("모델이 다운로드되지 않았습니다.")
                    .foregroundStyle(.secondary)
                Text("모델 다운로드는 다음 단계에서 구현됩니다.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("단축키: ⌥Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 260)
    }
}
