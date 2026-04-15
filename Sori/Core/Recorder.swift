@preconcurrency import AVFoundation
import CoreAudio
import Foundation

final class Recorder: @unchecked Sendable {
    enum RecorderError: Error, LocalizedError {
        case setupFailed(String)
        case deviceSelectionFailed(String)

        var errorDescription: String? {
            switch self {
            case .setupFailed(let msg): return "녹음 초기화 실패: \(msg)"
            case .deviceSelectionFailed(let msg): return "입력 장치 선택 실패: \(msg)"
            }
        }
    }

    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var tempURL: URL?
    private var isRunning = false
    private var callbackCount = 0
    private var levelCallback: (@Sendable (Float) -> Void)?

    /// 녹음 시작.
    /// - Parameters:
    ///   - deviceID: AVCaptureDevice.uniqueID. nil이면 시스템 기본 입력.
    ///   - levelCallback: 매 tap 버퍼마다 RMS/peak 레벨을 전달 (백그라운드 스레드에서 호출)
    func start(deviceID: String?, levelCallback: (@Sendable (Float) -> Void)?) throws {
        guard !isRunning else { return }

        engine.reset()
        engine.inputNode.removeTap(onBus: 0)

        // 1. 특정 디바이스 선택이 요청되면 Core Audio HAL로 inputNode의 AudioUnit에 설정.
        //    engine.prepare() 이전에 호출해야 유효함.
        if let deviceID, !deviceID.isEmpty {
            try applyInputDevice(deviceID)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw RecorderError.setupFailed("입력 포맷이 유효하지 않습니다 (sampleRate=0)")
        }

        // 2. 출력 파일 준비
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
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
        } catch {
            throw RecorderError.setupFailed("출력 파일 생성 실패: \(error.localizedDescription)")
        }
        let targetFormat = audioFile.processingFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.setupFailed("오디오 컨버터 생성 실패")
        }

        self.audioFile = audioFile
        self.targetFormat = targetFormat
        self.converter = converter
        self.tempURL = tempURL
        self.levelCallback = levelCallback
        self.callbackCount = 0

        // 3. tap 설치
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecorderError.setupFailed("engine.start() 실패: \(error.localizedDescription)")
        }
        isRunning = true

        NSLog(
            "[Sori][Recorder] started deviceID=%@ inputFormat=%@ targetFormat=%@",
            deviceID ?? "system-default",
            "\(inputFormat)",
            "\(targetFormat)"
        )
    }

    private func applyInputDevice(_ uniqueID: String) throws {
        guard let devID = AudioDeviceList.audioDeviceID(forUniqueID: uniqueID) else {
            throw RecorderError.deviceSelectionFailed("uniqueID \(uniqueID)에 해당하는 CoreAudio 장치 없음")
        }
        guard let inputUnit = engine.inputNode.audioUnit else {
            throw RecorderError.deviceSelectionFailed("inputNode의 audioUnit 접근 불가")
        }
        var device = devID
        let status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw RecorderError.deviceSelectionFailed("AudioUnitSetProperty 실패 status=\(status)")
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat, let audioFile else { return }

        let inputSampleRate = buffer.format.sampleRate
        let ratio = Self.sampleRate / inputSampleRate
        let outputCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return
        }

        let feeder = RecorderConversionFeeder(buffer: buffer)
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            feeder.next(outStatus: outStatus)
        }

        if error == nil, status != .error, outputBuffer.frameLength > 0 {
            try? audioFile.write(from: outputBuffer)

            if let cb = levelCallback, let floatData = outputBuffer.floatChannelData?.pointee {
                let count = Int(outputBuffer.frameLength)
                var peak: Float = 0
                for i in 0..<count {
                    let v = abs(floatData[i])
                    if v > peak { peak = v }
                }
                cb(min(peak, 1.0))
            }

            callbackCount += 1
        }
    }

    func stop() -> URL? {
        guard isRunning else { return nil }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let url = tempURL
        let length = audioFile?.length ?? 0
        let count = callbackCount
        audioFile = nil
        converter = nil
        targetFormat = nil
        tempURL = nil
        levelCallback = nil
        callbackCount = 0

        let urlName = url?.lastPathComponent ?? "nil"
        NSLog("[Sori][Recorder] stopped url=\(urlName) length=\(length) callbacks=\(count)")
        return url
    }

    func cancel() {
        if let url = stop() {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private final class RecorderConversionFeeder: @unchecked Sendable {
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
