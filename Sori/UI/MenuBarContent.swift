import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject var history: HistoryStore
    @State private var query: String = ""

    private let visibleLimit: Int = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader
            Divider()
            searchField
            historyList
            Divider()
            footerButtons
        }
        .frame(width: 380)
        .padding(.vertical, 8)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: appState.menuBarSymbolName)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sori").font(.headline)
                Text(appState.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("검색", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var filteredEntries: [HistoryEntry] {
        let base = history.search(query: query)
        return Array(base.prefix(visibleLimit))
    }

    @ViewBuilder
    private var historyList: some View {
        if history.entries.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        HistoryRowView(entry: entry, appState: appState, history: history)
                        Divider().padding(.leading, 12)
                    }
                    if history.entries.count > visibleLimit && query.isEmpty {
                        Text("더 많은 기록은 설정 창에서 확인할 수 있습니다.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(12)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("아직 전사 기록이 없어요")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("⌥Space 로 녹음을 시작하세요")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var footerButtons: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                appState.addFilesToQueue()
            } label: {
                Label("파일 전사…", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button {
                appState.showFileQueue()
            } label: {
                Label("파일 전사 큐 보기", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider().padding(.vertical, 4)

            Button {
                openSettings()
            } label: {
                Label("설정…", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .keyboardShortcut(",")

            Button {
                history.clear()
            } label: {
                Label("히스토리 모두 지우기", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .disabled(history.entries.isEmpty)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("종료", systemImage: "power")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .keyboardShortcut("q")
        }
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

private struct HistoryRowView: View {
    let entry: HistoryEntry
    @ObservedObject var appState: AppState
    @ObservedObject var history: HistoryStore
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.isFileSource ? "doc.fill" : "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(entry.createdAt, style: .relative)
                    if entry.isFileSource, let path = entry.originalFilePath {
                        Text("·")
                        Text((path as NSString).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovering ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            appState.reuseHistoryEntry(id: entry.id, paste: true)
        }
        .contextMenu {
            Button("클립보드에 복사") {
                appState.reuseHistoryEntry(id: entry.id, paste: false)
            }
            Button("삭제", role: .destructive) {
                history.remove(id: entry.id)
            }
            if entry.isFileSource, let path = entry.originalFilePath {
                Divider()
                Button("Finder에서 보기") {
                    let url = URL(fileURLWithPath: path)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("원본 파일 열기") {
                    let url = URL(fileURLWithPath: path)
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
