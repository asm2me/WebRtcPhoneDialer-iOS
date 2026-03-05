import Foundation

class SettingsViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var sipDomain: String = ""
    @Published var signalingServerUrl: String = ""
    @Published var authToken: String = ""
    @Published var stunServer: String = ""
    @Published var turnServer: String = ""
    @Published var turnUsername: String = ""
    @Published var turnPassword: String = ""
    @Published var iceServers: String = ""
    @Published var enableAudio: Bool = true
    @Published var inputVolume: Double = 100
    @Published var outputVolume: Double = 100
    @Published var echoCancellation: Bool = true
    @Published var noiseSuppression: Bool = true
    @Published var ringVolume: Double = 80
    @Published var audioCodecName: String = "PCMU"
    @Published var enableVideo: Bool = false

    static let audioCodecOptions = ["PCMU", "PCMA", "Opus", "G.722"]

    private let sipService: SIPService

    init(sipService: SIPService) {
        self.sipService = sipService
        loadSettings()
    }

    func loadSettings() {
        let settings = AppSettings.load()
        username = settings.username
        password = settings.password
        sipDomain = settings.sipDomain
        signalingServerUrl = settings.signalingServerUrl
        authToken = settings.authToken
        stunServer = settings.stunServer
        turnServer = settings.turnServer
        turnUsername = settings.turnUsername
        turnPassword = settings.turnPassword
        iceServers = settings.iceServers
        enableAudio = settings.enableAudio
        inputVolume = Double(settings.inputVolume)
        outputVolume = Double(settings.outputVolume)
        echoCancellation = settings.echoCancellation
        noiseSuppression = settings.noiseSuppression
        ringVolume = Double(settings.ringVolume)
        audioCodecName = settings.audioCodecName
        enableVideo = settings.enableVideo
    }

    func save() {
        var settings = AppSettings()
        settings.username = username
        settings.password = password
        settings.sipDomain = sipDomain
        settings.signalingServerUrl = signalingServerUrl
        settings.authToken = authToken
        settings.stunServer = stunServer
        settings.turnServer = turnServer
        settings.turnUsername = turnUsername
        settings.turnPassword = turnPassword
        settings.iceServers = iceServers
        settings.enableAudio = enableAudio
        settings.inputVolume = Int(inputVolume)
        settings.outputVolume = Int(outputVolume)
        settings.echoCancellation = echoCancellation
        settings.noiseSuppression = noiseSuppression
        settings.ringVolume = Int(ringVolume)
        settings.audioCodecName = audioCodecName
        settings.enableVideo = enableVideo

        sipService.configure(settings)
    }
}
