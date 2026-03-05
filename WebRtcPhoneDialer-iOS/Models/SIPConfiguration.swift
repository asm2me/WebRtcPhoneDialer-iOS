import Foundation

struct SIPConfiguration {
    var username: String = ""
    var password: String = ""
    var sipDomain: String = ""
    var signalingServerUrl: String = ""
    var authToken: String = ""
    var stunServer: String = ""
    var turnServer: String = ""
    var turnUsername: String = ""
    var turnPassword: String = ""
    var iceServers: [String] = []
    var enableAudio: Bool = true
    var inputVolume: Int = 100
    var outputVolume: Int = 100
    var echoCancellation: Bool = true
    var noiseSuppression: Bool = true
    var audioCodec: AudioCodec = .pcmu
    var publicIPAddress: String?
    var localIPAddress: String?

    enum AudioCodec: String {
        case pcmu = "PCMU"
        case pcma = "PCMA"
        case opus = "Opus"
        case g722 = "G.722"

        var payloadType: UInt8 {
            switch self {
            case .pcmu: return 0
            case .pcma: return 8
            case .opus: return 111
            case .g722: return 9
            }
        }

        var clockRate: Int {
            switch self {
            case .pcmu, .pcma: return 8000
            case .opus: return 48000
            case .g722: return 8000
            }
        }

        var rtpMapString: String {
            switch self {
            case .pcmu: return "PCMU/8000"
            case .pcma: return "PCMA/8000"
            case .opus: return "opus/48000/2"
            case .g722: return "G722/8000"
            }
        }
    }

    init(from settings: AppSettings) {
        self.username = settings.username
        self.password = settings.password
        self.sipDomain = settings.sipDomain
        self.signalingServerUrl = settings.signalingServerUrl
        self.authToken = settings.authToken
        self.stunServer = settings.stunServer
        self.turnServer = settings.turnServer
        self.turnUsername = settings.turnUsername
        self.turnPassword = settings.turnPassword
        self.enableAudio = settings.enableAudio
        self.inputVolume = settings.inputVolume
        self.outputVolume = settings.outputVolume
        self.echoCancellation = settings.echoCancellation
        self.noiseSuppression = settings.noiseSuppression
        self.audioCodec = AudioCodec(rawValue: settings.audioCodecName) ?? .pcmu

        if !settings.iceServers.isEmpty {
            self.iceServers = settings.iceServers
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    init() {}
}
