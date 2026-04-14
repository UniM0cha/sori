import AVFoundation
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
}
