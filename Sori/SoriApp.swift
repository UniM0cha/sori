import SwiftUI

@main
struct SoriApp: App {
    var body: some Scene {
        MenuBarExtra("Sori", systemImage: "waveform") {
            Text("Sori")
                .font(.headline)
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)
    }
}
