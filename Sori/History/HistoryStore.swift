import Foundation
import SwiftUI

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private let fileURL: URL
    private let maxEntries: Int

    init(fileURL: URL = AppSupportDirectory.historyFile, maxEntries: Int = 1000) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        load()
    }

    func append(text: String, duration: TimeInterval, source: HistoryEntry.Source = .live) {
        let entry = HistoryEntry(
            text: text,
            durationSeconds: duration,
            source: source
        )
        entries.insert(entry, at: 0)
        trimAndPersist()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func bump(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: idx)
        entries.insert(entry, at: 0)
        persist()
    }

    func search(query: String) -> [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    private func trimAndPersist() {
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([HistoryEntry].self, from: data)
            self.entries = loaded
        } catch {
            // Corrupted or migration issue — back up and start fresh
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("backup-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            self.entries = []
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Silent fail — history is best-effort
        }
    }
}
