@preconcurrency import AVFoundation
import Foundation

enum AudioFileDecoder {
    enum DecoderError: Error, LocalizedError {
        case cannotReadFile(String)
        case cannotCreateConverter
        case cannotCreateBuffer

        var errorDescription: String? {
            switch self {
            case .cannotReadFile(let msg): return "파일을 읽을 수 없습니다: \(msg)"
            case .cannotCreateConverter: return "오디오 변환기 생성에 실패했습니다"
            case .cannotCreateBuffer: return "오디오 버퍼 생성에 실패했습니다"
            }
        }
    }

    static let targetSampleRate: Double = 16_000

    static func decodeTo16kWav(source: URL) throws -> URL {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: source)
        } catch {
            throw DecoderError.cannotReadFile(error.localizedDescription)
        }

        let inputFormat = file.processingFormat

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw DecoderError.cannotCreateConverter
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw DecoderError.cannotCreateConverter
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sori-file-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: settings)

        let chunkFrames: AVAudioFrameCount = 8192
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: chunkFrames) else {
            throw DecoderError.cannotCreateBuffer
        }

        while file.framePosition < file.length {
            inputBuffer.frameLength = 0
            do {
                try file.read(into: inputBuffer, frameCount: chunkFrames)
            } catch {
                break
            }
            if inputBuffer.frameLength == 0 { break }

            let ratio = targetSampleRate / inputFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 1024
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputCapacity
            ) else {
                throw DecoderError.cannotCreateBuffer
            }

            let feeder = ConversionFeeder(buffer: inputBuffer)
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                feeder.next(outStatus: outStatus)
            }

            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }

            if status == .error { break }
        }

        return outputURL
    }
}

private final class ConversionFeeder: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var consumed = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if consumed {
            outStatus.pointee = .endOfStream
            return nil
        }
        outStatus.pointee = .haveData
        consumed = true
        return buffer
    }
}
