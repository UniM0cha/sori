import AppKit
import Foundation
import SwiftUI

@MainActor
final class FileTranscriptionQueue: ObservableObject {
    struct Job: Identifiable, Equatable, Sendable {
        enum Status: Equatable, Sendable {
            case pending
            case decoding
            case transcribing
            case done
            case failed(String)
        }

        let id: UUID
        let sourceURL: URL
        var status: Status
        var resultText: String?

        init(sourceURL: URL) {
            self.id = UUID()
            self.sourceURL = sourceURL
            self.status = .pending
            self.resultText = nil
        }
    }

    @Published private(set) var jobs: [Job] = []

    private let transcriber: Transcriber
    private let history: HistoryStore
    private var drainTask: Task<Void, Never>?

    init(transcriber: Transcriber, history: HistoryStore) {
        self.transcriber = transcriber
        self.history = history
    }

    var hasCompletedJobs: Bool {
        jobs.contains { job in
            if case .done = job.status { return true }
            if case .failed = job.status { return true }
            return false
        }
    }

    func enqueue(_ urls: [URL]) {
        let newJobs = urls.map { Job(sourceURL: $0) }
        jobs.append(contentsOf: newJobs)
        if drainTask == nil {
            drainTask = Task { [weak self] in
                await self?.drain()
                await MainActor.run { self?.drainTask = nil }
            }
        }
    }

    func remove(id: UUID) {
        jobs.removeAll { $0.id == id }
    }

    func clearCompleted() {
        jobs.removeAll { job in
            switch job.status {
            case .done, .failed: return true
            default: return false
            }
        }
    }

    private func drain() async {
        while let index = nextPendingIndex() {
            jobs[index].status = .decoding
            let job = jobs[index]
            do {
                let wavURL = try await Task.detached(priority: .userInitiated) {
                    try AudioFileDecoder.decodeTo16kWav(source: job.sourceURL)
                }.value

                jobs[index].status = .transcribing

                let prefs = PreferencesSnapshot()
                let language: String? = prefs.asrLanguage == "auto" ? nil : prefs.asrLanguage
                let customWords = prefs.customWords

                let text = try await transcriber.transcribe(
                    audioFile: wavURL,
                    language: language,
                    context: customWords.isEmpty ? nil : customWords
                )
                try? FileManager.default.removeItem(at: wavURL)

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                history.append(
                    text: trimmed,
                    duration: 0,
                    source: .file(bookmark: nil, originalPath: job.sourceURL.path)
                )
                writeTxt(near: job.sourceURL, text: trimmed)

                if let still = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[still].resultText = trimmed
                    jobs[still].status = .done
                }
            } catch {
                if let still = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[still].status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func nextPendingIndex() -> Int? {
        jobs.firstIndex { $0.status == .pending }
    }

    private func writeTxt(near source: URL, text: String) {
        let base = source.deletingPathExtension()
        let txtURL = base.appendingPathExtension("txt")
        do {
            try text.write(to: txtURL, atomically: true, encoding: .utf8)
        } catch {
            let fallback = AppSupportDirectory.base
                .appendingPathComponent("transcripts", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            let name = source.deletingPathExtension().lastPathComponent
            let fallbackURL = fallback.appendingPathComponent("\(name).txt")
            try? text.write(to: fallbackURL, atomically: true, encoding: .utf8)
        }
    }
}
