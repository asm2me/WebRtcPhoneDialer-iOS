import Foundation
import AVFoundation

struct AudioDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let portType: AVAudioSession.Port

    var isBuiltInSpeaker: Bool {
        portType == .builtInSpeaker
    }

    var isBuiltInReceiver: Bool {
        portType == .builtInReceiver
    }

    var isBluetooth: Bool {
        portType == .bluetoothA2DP || portType == .bluetoothLE || portType == .bluetoothHFP
    }
}
