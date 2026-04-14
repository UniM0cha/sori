import Foundation
import Hub

actor ModelDownloader {
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
        try await hub.snapshot(from: modelId) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }
}
