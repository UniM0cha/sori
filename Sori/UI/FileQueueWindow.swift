import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FileQueueWindowController {
    private var window: NSWindow?
    private let queue: FileTranscriptionQueue

    init(queue: FileTranscriptionQueue) {
        self.queue = queue
    }

    func show() {
        if window == nil {
            let view = FileQueueView(queue: queue) { [weak self] in
                self?.presentOpenPanel()
            }
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sori — 파일 전사"
            window.center()
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "전사할 오디오 파일을 선택하세요"
        panel.prompt = "전사"
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.begin { [weak self] response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            Task { @MainActor [weak self] in
                self?.queue.enqueue(urls)
                self?.show()
            }
        }
    }
}

struct FileQueueView: View {
    @ObservedObject var queue: FileTranscriptionQueue
    let onAddFiles: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if queue.jobs.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(queue.jobs) { job in
                        FileJobRow(job: job, queue: queue)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Text("파일 전사 큐")
                .font(.headline)
            Spacer()
            Button {
                onAddFiles()
            } label: {
                Label("파일 추가", systemImage: "plus")
            }
            Button {
                queue.clearCompleted()
            } label: {
                Label("완료된 항목 지우기", systemImage: "checklist")
            }
            .disabled(!queue.hasCompletedJobs)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("전사할 오디오 파일을 추가해 보세요")
                .foregroundStyle(.secondary)
            Text("wav, mp3, m4a, aac, flac 등 Core Audio가 지원하는 포맷")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileJobRow: View {
    let job: FileTranscriptionQueue.Job
    @ObservedObject var queue: FileTranscriptionQueue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceURL.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusLine
            }
            Spacer()
            if case .done = job.status {
                Button {
                    let url = job.sourceURL.deletingPathExtension().appendingPathExtension("txt")
                    if FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help(".txt 결과 열기")
            }
            Button {
                queue.remove(id: job.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        Group {
            switch job.status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            case .decoding, .transcribing:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch job.status {
        case .pending:
            Text("대기 중")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .decoding:
            Text("디코딩 중…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .transcribing:
            Text("전사 중…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .done:
            Text("완료")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed(let msg):
            Text(msg)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}
