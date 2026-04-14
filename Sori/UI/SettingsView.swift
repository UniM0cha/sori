import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("일반", systemImage: "gear") }
            ModelSettingsTab()
                .tabItem { Label("모델", systemImage: "cpu") }
            HistorySettingsTab()
                .tabItem { Label("히스토리", systemImage: "clock") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettingsTab: View {
    var body: some View {
        Form {
            Section("단축키") {
                KeyboardShortcuts.Recorder(for: .toggleRecording) {
                    Text("녹음 시작 / 종료")
                }
            }
            Section("안내") {
                Text("Option+Space는 기본값이며 언제든 변경할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelSettingsTab: View {
    @AppStorage(PreferenceKeys.modelId) private var modelId: String = ModelIdentifier.defaultModel
    @AppStorage(PreferenceKeys.modelIdleTimeoutSeconds) private var idleTimeout: Double = 300
    @AppStorage(PreferenceKeys.eagerLoadModelOnLaunch) private var eagerLoad: Bool = false
    @AppStorage(PreferenceKeys.asrLanguage) private var asrLanguage: String = "auto"
    @AppStorage(PreferenceKeys.customWords) private var customWords: String = ""

    private let idleOptions: [(String, Double)] = [
        ("1분", 60),
        ("5분", 300),
        ("10분", 600),
        ("30분", 1800),
        ("무제한", 0),
    ]

    private let languageOptions: [(String, String)] = [
        ("자동 감지", "auto"),
        ("한국어", "ko"),
        ("English", "en"),
        ("日本語", "ja"),
        ("中文", "zh"),
    ]

    var body: some View {
        Form {
            Section("모델") {
                Picker("모델", selection: $modelId) {
                    ForEach(ModelIdentifier.available, id: \.self) { id in
                        Text(shortName(for: id)).tag(id)
                    }
                }
                Text("모델을 변경하면 재시작 후 새 모델을 다운로드합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("메모리") {
                Picker("유휴 시 언로드", selection: $idleTimeout) {
                    ForEach(idleOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                Toggle("앱 시작 시 모델 미리 로드", isOn: $eagerLoad)
                Text("미리 로드하면 첫 녹음 지연이 사라지지만, 시작 즉시 ~4 GB 메모리가 점유됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("전사 언어") {
                Picker("언어", selection: $asrLanguage) {
                    ForEach(languageOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
            }
            Section("자주 쓰는 단어") {
                TextEditor(text: $customWords)
                    .font(.body)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                Text("쉼표로 구분된 고유명사나 전문 용어를 적어두면 전사 정확도가 올라갑니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortName(for id: String) -> String {
        guard let last = id.split(separator: "/").last else { return id }
        return String(last)
    }
}

private struct HistorySettingsTab: View {
    @AppStorage(PreferenceKeys.historyMaxEntries) private var maxEntries: Int = 1000
    @AppStorage(PreferenceKeys.historyRetentionDays) private var retentionDays: Int = 0

    private let retentionOptions: [(String, Int)] = [
        ("무제한", 0),
        ("30일", 30),
        ("7일", 7),
        ("1일", 1),
    ]

    private let maxOptions: [Int] = [100, 500, 1000, 2000, 5000]

    var body: some View {
        Form {
            Section("보관") {
                Picker("보존 기간", selection: $retentionDays) {
                    ForEach(retentionOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                Picker("최대 개수", selection: $maxEntries) {
                    ForEach(maxOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                Text("오래된 기록은 최대 개수를 넘으면 자동으로 삭제됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
