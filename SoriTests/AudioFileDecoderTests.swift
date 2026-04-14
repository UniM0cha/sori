@preconcurrency import AVFoundation
import XCTest
@testable import Sori

final class AudioFileDecoderTests: XCTestCase {
    private var workingDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sori-decoder-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let workingDirectory {
            try? FileManager.default.removeItem(at: workingDirectory)
        }
        workingDirectory = nil
        try super.tearDownWithError()
    }

    /// Writes a tiny RIFF/WAV file by hand. Using AVAudioFile(forWriting:) here
    /// proved flaky under the test runner; a manually assembled PCM wav avoids
    /// the AVAudioEngine-style initialization entirely.
    private func makeSyntheticWav(
        sampleRate: Int,
        channels: Int,
        durationSeconds: Double
    ) throws -> URL {
        let name = "source-\(sampleRate)-\(channels)ch.wav"
        let url = workingDirectory.appendingPathComponent(name)

        let frameCount = Int(Double(sampleRate) * durationSeconds)
        let bytesPerSample = 2
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample
        let dataSize = frameCount * channels * bytesPerSample
        let riffSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLE(UInt32(riffSize), to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendLE(UInt32(16), to: &data)               // fmt chunk size
        appendLE(UInt16(1), to: &data)                // PCM
        appendLE(UInt16(channels), to: &data)
        appendLE(UInt32(sampleRate), to: &data)
        appendLE(UInt32(byteRate), to: &data)
        appendLE(UInt16(blockAlign), to: &data)
        appendLE(UInt16(16), to: &data)               // bits per sample
        data.append(contentsOf: "data".utf8)
        appendLE(UInt32(dataSize), to: &data)

        let frequency: Double = 440
        let amplitude: Double = 3_276
        for i in 0..<frameCount {
            let sample = Int16(amplitude * sin(2.0 * .pi * frequency * Double(i) / Double(sampleRate)))
            for _ in 0..<channels {
                appendLE(sample, to: &data)
            }
        }

        try data.write(to: url)
        return url
    }

    private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    func testDecodesStereo44kToMono16kInt16() throws {
        let source = try makeSyntheticWav(sampleRate: 44_100, channels: 2, durationSeconds: 0.5)

        let output = try AudioFileDecoder.decodeTo16kWav(source: source)
        defer { try? FileManager.default.removeItem(at: output) }

        let decoded = try AVAudioFile(forReading: output)
        XCTAssertEqual(decoded.processingFormat.sampleRate, 16_000, accuracy: 0.1)
        XCTAssertEqual(decoded.processingFormat.channelCount, 1)
        XCTAssertGreaterThan(decoded.length, 0)
    }

    func testDecodesMono16kInputIsPassThroughSize() throws {
        let source = try makeSyntheticWav(sampleRate: 16_000, channels: 1, durationSeconds: 0.25)

        let output = try AudioFileDecoder.decodeTo16kWav(source: source)
        defer { try? FileManager.default.removeItem(at: output) }

        let decoded = try AVAudioFile(forReading: output)
        XCTAssertEqual(decoded.processingFormat.sampleRate, 16_000, accuracy: 0.1)
        XCTAssertEqual(decoded.processingFormat.channelCount, 1)
        // Should be roughly 4000 frames for 0.25s of 16 kHz audio (allow generous slack
        // for converter padding).
        XCTAssertGreaterThan(decoded.length, 3_000)
        XCTAssertLessThan(decoded.length, 6_000)
    }

    func testDecodes48kStereoToMono16k() throws {
        let source = try makeSyntheticWav(sampleRate: 48_000, channels: 2, durationSeconds: 0.2)

        let output = try AudioFileDecoder.decodeTo16kWav(source: source)
        defer { try? FileManager.default.removeItem(at: output) }

        let decoded = try AVAudioFile(forReading: output)
        XCTAssertEqual(decoded.processingFormat.sampleRate, 16_000, accuracy: 0.1)
        XCTAssertEqual(decoded.processingFormat.channelCount, 1)
    }

    func testSyntheticWavFileIsReadable() throws {
        let source = try makeSyntheticWav(sampleRate: 16_000, channels: 1, durationSeconds: 0.1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let file = try AVAudioFile(forReading: source)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000, accuracy: 0.1)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
    }
}
