import AVFoundation
import Foundation

final class Recorder: @unchecked Sendable {
    enum RecorderError: Error {
        case setupFailed(String)
    }

    static let sampleRate: Double = 16_000.0

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var tempURL: URL?
    private var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw RecorderError.setupFailed("no input device")
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw RecorderError.setupFailed("target format")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.setupFailed("converter")
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sori-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        let audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)

        self.targetFormat = targetFormat
        self.converter = converter
        self.tempURL = tempURL
        self.audioFile = audioFile

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat, let audioFile else { return }

        let inputSampleRate = buffer.format.sampleRate
        let estimatedOutput = Double(buffer.frameLength) * Self.sampleRate / inputSampleRate
        let outputCapacity = AVAudioFrameCount(ceil(estimatedOutput)) + 1024

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else { return }

        var error: NSError?
        var consumed = false
        _ = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            consumed = true
            return buffer
        }

        if error == nil, outputBuffer.frameLength > 0 {
            try? audioFile.write(from: outputBuffer)
        }
    }

    func stop() -> URL? {
        guard isRunning else { return nil }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let url = tempURL
        audioFile = nil
        converter = nil
        targetFormat = nil
        tempURL = nil
        return url
    }

    func cancel() {
        if let url = stop() {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
