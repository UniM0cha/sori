import Foundation
import Hub

actor ModelDownloader {
    enum DownloaderError: Error, LocalizedError {
        case bundledTokenizerMissing

        var errorDescription: String? {
            switch self {
            case .bundledTokenizerMissing:
                return "앱 리소스에 tokenizer.json이 포함되어 있지 않습니다"
            }
        }
    }

    private let hub: HubApi
    private let downloadBase: URL

    init(downloadBase: URL = AppSupportDirectory.base) {
        self.downloadBase = downloadBase
        self.hub = HubApi(downloadBase: downloadBase)
    }

    /// HubApi lays out downloads as `<downloadBase>/models/<repoId>`.
    func localPath(for modelId: String) -> URL {
        downloadBase
            .appending(path: "models")
            .appending(path: modelId)
    }

    func isCached(modelId: String) -> Bool {
        let path = localPath(for: modelId)
        let configURL = path.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configURL.path)
    }

    /// Download the entire repo. progressHandler is called with fractionCompleted in [0, 1].
    /// If already cached, snapshot() finishes almost immediately.
    @discardableResult
    func ensureDownloaded(
        modelId: String,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        let path = try await hub.snapshot(from: modelId) { progress in
            progressHandler(progress.fractionCompleted)
        }
        try injectBundledTokenizerIfNeeded(at: path)
        return path
    }

    /// Ensure a `tokenizer.json` exists at `modelFolder`. All mlx-community
    /// Qwen3-ASR repos ship with the legacy vocab.json + merges.txt layout only,
    /// but swift-transformers strictly requires tokenizer.json. We build it
    /// offline from Qwen3-ASR's vocab/merges/config using Python transformers
    /// and ship it as a bundle resource; this method copies it into place
    /// after download (or on first run with an older cache).
    func injectBundledTokenizerIfNeeded(at modelFolder: URL) throws {
        let destination = modelFolder.appendingPathComponent("tokenizer.json")
        if FileManager.default.fileExists(atPath: destination.path) {
            return
        }
        guard let bundled = Bundle.main.url(forResource: "tokenizer", withExtension: "json") else {
            throw DownloaderError.bundledTokenizerMissing
        }
        try FileManager.default.copyItem(at: bundled, to: destination)
    }
}
