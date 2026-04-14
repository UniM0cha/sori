import Foundation

enum PreferenceKeys {
    static let modelId = "modelId"
    static let modelIdleTimeoutSeconds = "modelIdleTimeoutSeconds"
    static let asrLanguage = "asrLanguage"
    static let customWords = "customWords"
    static let historyMaxEntries = "historyMaxEntries"
    static let historyRetentionDays = "historyRetentionDays"
    static let eagerLoadModelOnLaunch = "eagerLoadModelOnLaunch"
    static let hasCompletedWelcome = "hasCompletedWelcome"
}

enum ModelIdentifier {
    static let defaultModel = "mlx-community/Qwen3-ASR-1.7B-bf16"

    static let available: [String] = [
        "mlx-community/Qwen3-ASR-1.7B-bf16",
        "mlx-community/Qwen3-ASR-1.7B-8bit",
        "mlx-community/Qwen3-ASR-1.7B-6bit",
        "mlx-community/Qwen3-ASR-1.7B-4bit",
        "mlx-community/Qwen3-ASR-0.6B-bf16",
        "mlx-community/Qwen3-ASR-0.6B-8bit",
        "mlx-community/Qwen3-ASR-0.6B-6bit",
        "mlx-community/Qwen3-ASR-0.6B-4bit",
    ]
}

extension UserDefaults {
    static func registerSoriDefaults(on defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            PreferenceKeys.modelId: ModelIdentifier.defaultModel,
            PreferenceKeys.modelIdleTimeoutSeconds: 300.0,
            PreferenceKeys.asrLanguage: "auto",
            PreferenceKeys.customWords: "",
            PreferenceKeys.historyMaxEntries: 1000,
            PreferenceKeys.historyRetentionDays: 0,
            PreferenceKeys.eagerLoadModelOnLaunch: false,
            PreferenceKeys.hasCompletedWelcome: false,
        ])
    }
}

struct PreferencesSnapshot: Sendable {
    var modelId: String
    var modelIdleTimeoutSeconds: TimeInterval
    var asrLanguage: String
    var customWords: String
    var historyMaxEntries: Int
    var historyRetentionDays: Int
    var eagerLoadModelOnLaunch: Bool
    var hasCompletedWelcome: Bool

    init(defaults: UserDefaults = .standard) {
        self.modelId = defaults.string(forKey: PreferenceKeys.modelId) ?? ModelIdentifier.defaultModel
        let rawTimeout = defaults.double(forKey: PreferenceKeys.modelIdleTimeoutSeconds)
        self.modelIdleTimeoutSeconds = rawTimeout > 0 ? rawTimeout : 300.0
        self.asrLanguage = defaults.string(forKey: PreferenceKeys.asrLanguage) ?? "auto"
        self.customWords = defaults.string(forKey: PreferenceKeys.customWords) ?? ""
        let rawMax = defaults.integer(forKey: PreferenceKeys.historyMaxEntries)
        self.historyMaxEntries = rawMax > 0 ? rawMax : 1000
        self.historyRetentionDays = defaults.integer(forKey: PreferenceKeys.historyRetentionDays)
        self.eagerLoadModelOnLaunch = defaults.bool(forKey: PreferenceKeys.eagerLoadModelOnLaunch)
        self.hasCompletedWelcome = defaults.bool(forKey: PreferenceKeys.hasCompletedWelcome)
    }
}

enum AppSupportDirectory {
    static var base: URL {
        let fm = FileManager.default
        let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sori", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var models: URL {
        let url = base.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var historyFile: URL {
        base.appendingPathComponent("history.json")
    }
}
