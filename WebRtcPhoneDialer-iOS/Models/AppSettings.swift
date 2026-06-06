import Foundation

struct AppSettings: Codable {
    // SIP credentials
    var username: String = ""
    var password: String = ""
    var sipDomain: String = ""

    // Signaling
    var signalingServerUrl: String = ""
    var authToken: String = ""

    // NAT traversal
    var stunServer: String = "stun:stun.l.google.com:19302"
    var turnServer: String = ""
    var turnUsername: String = ""
    var turnPassword: String = ""

    // ICE servers (newline-separated)
    var iceServers: String = ""

    // Audio
    var enableAudio: Bool = true
    var inputVolume: Int = 100
    var outputVolume: Int = 100
    var echoCancellation: Bool = true
    var noiseSuppression: Bool = true
    var ringVolume: Int = 80

    // Codecs
    var audioCodecName: String = "PCMU"
    var enableVideo: Bool = false
    var videoCodecName: String = "H.264"

    // MARK: - Persistence

    private static let userDefaultsKey = "WebRtcPhoneDialer.AppSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.userDefaultsKey)
        }
    }
}
