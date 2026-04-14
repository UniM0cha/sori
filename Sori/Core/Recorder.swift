@preconcurrency import AVFoundation
import Foundation

/// AVCaptureSession 기반 마이크 녹음.
/// - 특정 입력 디바이스 선택 가능 (AVCaptureDeviceInput)
/// - 레벨(RMS) 콜백으로 UI에 실시간 파형 데이터 노출
/// - 내부적으로 float32 non-interleaved 버퍼로 쓴 뒤 디스크에는 16kHz mono int16 PCM wav로 저장
final class Recorder: NSObject, @unchecked Sendable, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum RecorderError: Error, LocalizedError {
        case deviceNotFound
        case inputCreationFailed(String)
        case cannotAddInput
        case cannotAddOutput
        case cannotCreateConverter
        case fileCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .deviceNotFound: return "오디오 입력 장치를 찾을 수 없습니다"
            case .inputCreationFailed(let msg): return "입력 생성 실패: \(msg)"
            case .cannotAddInput: return "캡처 세션에 입력을 추가할 수 없습니다"
            case .cannotAddOutput: return "캡처 세션에 출력을 추가할 수 없습니다"
            case .cannotCreateConverter: return "오디오 변환기 생성에 실패했습니다"
            case .fileCreationFailed(let msg): return "녹음 파일 생성 실패: \(msg)"
            }
        }
    }

    static let sampleRate: Double = 16_000

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.solstice.sori.recorder", qos: .userInitiated)
    private var output: AVCaptureAudioDataOutput?

    private var audioFile: AVAudioFile?
    private var targetFormat: AVAudioFormat?
    private var sourceFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var tempURL: URL?
    private var isRunning = false
    private var callbackCount = 0

    private var levelCallback: (@Sendable (Float) -> Void)?

    /// 녹음 시작. 에러 시 throws.
    /// - Parameters:
    ///   - deviceID: `AVCaptureDevice.uniqueID`. nil이면 시스템 기본 입력 장치
    ///   - levelCallback: RMS 레벨(0~1)을 매 샘플 버퍼마다 전달 (백그라운드 큐에서 호출됨)
    func start(deviceID: String?, levelCallback: (@Sendable (Float) -> Void)?) throws {
        guard !isRunning else { return }

        guard let device = AudioDeviceList.captureDevice(for: deviceID) else {
            throw RecorderError.deviceNotFound
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecorderError.inputCreationFailed(error.localizedDescription)
        }

        session.beginConfiguration()

        // 이전 세션 정리
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw RecorderError.cannotAddInput
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw RecorderError.cannotAddOutput
        }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        self.output = output

        session.commitConfiguration()

        // 출력 파일 준비
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
        do {
            self.audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
        } catch {
            throw RecorderError.fileCreationFailed(error.localizedDescription)
        }
        // write(from:)는 processingFormat (non-interleaved float32)과 일치하는 버퍼를 요구
        self.targetFormat = audioFile?.processingFormat
        self.tempURL = tempURL
        self.levelCallback = levelCallback
        self.callbackCount = 0

        session.startRunning()
        isRunning = true

        let targetDesc = targetFormat?.description ?? "nil"
        NSLog("[Sori][Recorder] started device=\(device.localizedName) target=\(targetDesc)")
    }

    func stop() -> URL? {
        guard isRunning else { return nil }
        isRunning = false

        session.stopRunning()
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
        output = nil

        let url = tempURL
        let length = audioFile?.length ?? 0
        let count = callbackCount
        audioFile = nil
        converter = nil
        sourceFormat = nil
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

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let targetFormat,
              let audioFile
        else { return }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        else { return }

        // 소스 포맷 lazy 생성/재생성
        if sourceFormat == nil
            || sourceFormat?.sampleRate != asbd.mSampleRate
            || sourceFormat?.channelCount != asbd.mChannelsPerFrame
        {
            var streamDesc = asbd
            guard let src = AVAudioFormat(streamDescription: &streamDesc) else { return }
            sourceFormat = src
            converter = AVAudioConverter(from: src, to: targetFormat)
        }

        guard let sourceFormat, let converter else { return }

        // CMSampleBuffer → AVAudioPCMBuffer (소스 포맷)
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return }

        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(numSamples)
        ) else { return }
        sourceBuffer.frameLength = AVAudioFrameCount(numSamples)

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        // audioBufferList 의 데이터를 sourceBuffer에 복사
        if let srcData = audioBufferList.mBuffers.mData,
           let dstChannelData = sourceBuffer.floatChannelData?.pointee ?? nil
        {
            let bytesToCopy = Int(audioBufferList.mBuffers.mDataByteSize)
            memcpy(dstChannelData, srcData, bytesToCopy)
        } else if let srcData = audioBufferList.mBuffers.mData,
                  let int16Data = sourceBuffer.int16ChannelData?.pointee ?? nil
        {
            let bytesToCopy = Int(audioBufferList.mBuffers.mDataByteSize)
            memcpy(int16Data, srcData, bytesToCopy)
        }

        // 변환: 소스 → 타겟 (16kHz mono float32)
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else { return }

        let feeder = RecorderConversionFeeder(buffer: sourceBuffer)
        var error: NSError?
        let convertStatus = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            feeder.next(outStatus: outStatus)
        }
        if convertStatus == .error || error != nil { return }

        if outputBuffer.frameLength > 0 {
            try? audioFile.write(from: outputBuffer)

            // 레벨 계산 (peak abs) — 단순화
            if let callback = levelCallback, let floatData = outputBuffer.floatChannelData?.pointee {
                let count = Int(outputBuffer.frameLength)
                var peak: Float = 0
                for i in 0..<count {
                    let v = abs(floatData[i])
                    if v > peak { peak = v }
                }
                callback(min(peak, 1.0))
            }

            callbackCount += 1
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
