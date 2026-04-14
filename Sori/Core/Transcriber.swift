import Foundation
import MLXASR

actor Transcriber {
    enum TranscriberError: Error {
        case modelDirectoryMissing
        case cancelled
    }

    private var stt: Qwen3ASRSTT?
    private var lastUsedAt: Date = .distantPast
    private var idleUnloadTask: Task<Void, Never>?
    private var modelDirectory: URL?
    private var idleTimeout: TimeInterval = 300
    private var cancelRequested: Bool = false

    func configure(modelDirectory: URL, idleTimeout: TimeInterval) {
        self.modelDirectory = modelDirectory
        self.idleTimeout = idleTimeout
    }

    var isLoaded: Bool { stt != nil }

    func loadIfNeeded() async throws {
        if stt != nil { return }
        guard let modelDirectory else { throw TranscriberError.modelDirectoryMissing }
        let fresh = try await Qwen3ASRSTT.loadWithWarmup(from: modelDirectory)
        stt = fresh
    }

    func transcribe(
        audioFile url: URL,
        language: String? = nil,
        context: String? = nil
    ) async throws -> String {
        try await loadIfNeeded()
        guard let stt else { return "" }

        lastUsedAt = Date()
        cancelRequested = false
        scheduleIdleUnload()

        let languageHint = (language == "auto" || language?.isEmpty == true) ? nil : language
        let contextHint = (context?.isEmpty == true) ? nil : context

        let result = try await stt.transcribe(
            file: url,
            language: languageHint,
            context: contextHint
        )

        if cancelRequested {
            throw TranscriberError.cancelled
        }
        return result.text
    }

    func cancelCurrent() {
        cancelRequested = true
    }

    func unloadModel() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        stt = nil
        Qwen3ASRSTT.flushMemoryPool()
    }

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        let timeout = idleTimeout
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            await self?.unloadIfIdle()
        }
    }

    private func unloadIfIdle() {
        let elapsed = Date().timeIntervalSince(lastUsedAt)
        guard elapsed >= idleTimeout else { return }
        stt = nil
        Qwen3ASRSTT.flushMemoryPool()
    }
}
