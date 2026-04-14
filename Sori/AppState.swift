import AppKit
import Foundation
import SwiftUI

enum AppRecordingState: Sendable, Equatable {
    case idle
    case loadingModel
    case recording
    case transcribing
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var recordingState: AppRecordingState = .idle
    @Published private(set) var isBlinkOn: Bool = false
    @Published var modelCached: Bool = false
    @Published var downloadProgress: Double = 0.0

    let recorder: Recorder
    let transcriber: Transcriber
    let downloader: ModelDownloader

    private var blinkTimer: Timer?

    init(
        recorder: Recorder = Recorder(),
        transcriber: Transcriber = Transcriber(),
        downloader: ModelDownloader = ModelDownloader()
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.downloader = downloader
    }

    var isRecording: Bool {
        if case .recording = recordingState { return true }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = recordingState { return true }
        return false
    }

    var isLoadingModel: Bool {
        if case .loadingModel = recordingState { return true }
        return false
    }

    var isRecordingOrTranscribing: Bool {
        isRecording || isTranscribing
    }

    var menuBarSymbolName: String {
        switch recordingState {
        case .idle:
            return "waveform"
        case .loadingModel:
            return "arrow.down.circle"
        case .recording:
            return isBlinkOn ? "waveform.circle.fill" : "waveform"
        case .transcribing:
            return "waveform.path"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var statusLabel: String {
        switch recordingState {
        case .idle: return "준비됨"
        case .loadingModel: return "모델 로드 중…"
        case .recording: return "녹음 중"
        case .transcribing: return "전사 중…"
        case .error(let msg): return "오류: \(msg)"
        }
    }

    func bootstrap() async {
        let prefs = PreferencesSnapshot()
        let modelPath = await downloader.localPath(for: prefs.modelId)
        await transcriber.configure(
            modelDirectory: modelPath,
            idleTimeout: prefs.modelIdleTimeoutSeconds
        )
        let cached = await downloader.isCached(modelId: prefs.modelId)
        modelCached = cached

        if cached && prefs.eagerLoadModelOnLaunch {
            recordingState = .loadingModel
            do {
                try await transcriber.loadIfNeeded()
                recordingState = .idle
            } catch {
                recordingState = .error("모델 로드 실패: \(error.localizedDescription)")
            }
        }
    }

    func toggleRecording() {
        guard modelCached else {
            recordingState = .error("모델이 다운로드되지 않았습니다")
            return
        }
        if isRecording {
            stopAndTranscribe()
        } else if !isTranscribing, !isLoadingModel {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try recorder.start()
            recordingState = .recording
            startBlinking()
        } catch {
            recordingState = .error("녹음 시작 실패: \(error.localizedDescription)")
        }
    }

    private func stopAndTranscribe() {
        stopBlinking()
        let wavURL = recorder.stop()
        guard let wavURL else {
            recordingState = .idle
            return
        }
        recordingState = .transcribing

        let prefs = PreferencesSnapshot()
        let language: String? = prefs.asrLanguage == "auto" ? nil : prefs.asrLanguage
        let customWords = prefs.customWords

        Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: wavURL) }
            do {
                let text = try await self.transcriber.transcribe(
                    audioFile: wavURL,
                    language: language,
                    context: customWords.isEmpty ? nil : customWords
                )
                await MainActor.run {
                    if text.isEmpty {
                        self.recordingState = .idle
                        return
                    }
                    Clipboard.writeAndPaste(text)
                    self.recordingState = .idle
                }
            } catch is CancellationError {
                await MainActor.run { self.recordingState = .idle }
            } catch Transcriber.TranscriberError.cancelled {
                await MainActor.run { self.recordingState = .idle }
            } catch {
                await MainActor.run {
                    self.recordingState = .error("전사 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelRecording() {
        if isRecording {
            recorder.cancel()
            stopBlinking()
            recordingState = .idle
            return
        }
        if isTranscribing {
            Task { [weak self] in
                guard let self else { return }
                await self.transcriber.cancelCurrent()
                await MainActor.run { self.recordingState = .idle }
            }
        }
    }

    private func startBlinking() {
        stopBlinking()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.isBlinkOn.toggle()
            }
        }
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isBlinkOn = false
    }
}
