import AVFoundation
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: String           // AVCaptureDevice.uniqueID
    let name: String         // localizedName
    let isDefault: Bool
}

enum AudioDeviceList {
    /// macOS 오디오 입력 디바이스 목록. 시스템 기본 디바이스가 가장 앞에 오며 `isDefault`가 true.
    static func available() -> [AudioInputDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discovery.devices
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID

        return devices.map { device in
            AudioInputDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device.uniqueID == defaultID
            )
        }
    }

    /// 시스템 기본 오디오 입력 디바이스.
    static func systemDefault() -> AudioInputDevice? {
        guard let device = AVCaptureDevice.default(for: .audio) else { return nil }
        return AudioInputDevice(
            id: device.uniqueID,
            name: device.localizedName,
            isDefault: true
        )
    }

    /// 지정된 ID로 실제 AVCaptureDevice 인스턴스를 찾는다. nil이면 시스템 기본 디바이스.
    static func captureDevice(for id: String?) -> AVCaptureDevice? {
        if let id, let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        return AVCaptureDevice.default(for: .audio)
    }

    /// Core Audio HAL로 uniqueID에 해당하는 AudioDeviceID를 찾는다.
    /// AVCaptureDevice.uniqueID는 HAL의 kAudioDevicePropertyDeviceUID와 동일한 문자열.
    static func audioDeviceID(forUniqueID uid: String) -> AudioDeviceID? {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &propertySize)
        guard status == noErr, propertySize > 0 else { return nil }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(system, &address, 0, nil, &propertySize, &devices)
        guard status == noErr else { return nil }

        for device in devices {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfUID: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let uidStatus = AudioObjectGetPropertyData(
                device,
                &uidAddress,
                0,
                nil,
                &uidSize,
                &cfUID
            )
            guard uidStatus == noErr, let cfUID else { continue }
            let deviceUID = cfUID.takeRetainedValue() as String
            if deviceUID == uid {
                return device
            }
        }
        return nil
    }
}
