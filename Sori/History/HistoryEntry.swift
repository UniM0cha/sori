import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable, Sendable {
    enum Source: Codable, Hashable, Sendable {
        case live
        case file(bookmark: Data?, originalPath: String)
    }

    let id: UUID
    var text: String
    let createdAt: Date
    let durationSeconds: Double
    let source: Source

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        durationSeconds: Double,
        source: Source = .live
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.source = source
    }

    var characterCount: Int { text.count }

    var isFileSource: Bool {
        if case .file = source { return true }
        return false
    }

    var originalFilePath: String? {
        if case .file(_, let path) = source { return path }
        return nil
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }
}
