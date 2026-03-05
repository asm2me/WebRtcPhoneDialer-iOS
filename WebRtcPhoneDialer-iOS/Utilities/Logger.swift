import Foundation
import os

struct Log {
    static let sip = os.Logger(subsystem: "com.webrtcphonedialer", category: "SIP")
    static let rtp = os.Logger(subsystem: "com.webrtcphonedialer", category: "RTP")
    static let audio = os.Logger(subsystem: "com.webrtcphonedialer", category: "Audio")
    static let stun = os.Logger(subsystem: "com.webrtcphonedialer", category: "STUN")
    static let app = os.Logger(subsystem: "com.webrtcphonedialer", category: "App")
}
