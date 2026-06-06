import Foundation
import Network

class SIPService: ObservableObject {
    // MARK: - Published state
    @Published var registrationState: RegistrationState = .unregistered
    @Published var registrationMessage: String = "Not registered"
    @Published var currentCall: CallSession?
    @Published var micLevel: Float = 0
    @Published var speakerLevel: Float = 0
    @Published var publicIPAddress: String?
    @Published var sipLog: [SIPLogEntry] = []
    @Published var rtpLog: [String] = []
    @Published var isMuted: Bool = false
    @Published var isSpeakerOn: Bool = false

    // MARK: - Configuration
    private var config = SIPConfiguration()
    private var settings = AppSettings()

    // MARK: - Components
    private var wssChannel: WSSChannel?
    private var registrationAgent: SIPRegistrationAgent?
    private var userAgent: SIPUserAgent?
    private var rtpSession: RTPSession?
    private var audioService: AudioService?
    private let callKitManager = CallKitManager()
    private let transactionManager = SIPTransactionManager()

    // MARK: - State
    private var callStartTime: Date?
    private let sipLogMaxCount = 200
    private let rtpLogMaxCount = 200
    private let mainQueue = DispatchQueue.main

    var hasActiveCall: Bool {
        guard let call = currentCall else { return false }
        return [.initiating, .ringing, .connected, .onHold].contains(call.state)
    }

    var isRegistered: Bool {
        registrationState == .registered
    }

    // MARK: - Init

    init() {
        callKitManager.delegate = self
        settings = AppSettings.load()
        config = SIPConfiguration(from: settings)
        discoverLocalIP()
    }

    // MARK: - Configure

    func configure(_ newSettings: AppSettings) {
        settings = newSettings
        config = SIPConfiguration(from: newSettings)
        settings.save()
        discoverLocalIP()
    }

    func getConfiguration() -> SIPConfiguration {
        return config
    }

    // MARK: - Registration

    func register() async {
        guard !config.signalingServerUrl.isEmpty else {
            updateRegistration(.failed, message: "Signaling server URL not configured")
            return
        }
        guard !config.username.isEmpty else {
            updateRegistration(.failed, message: "Username not configured")
            return
        }

        updateRegistration(.registering, message: "Connecting to signaling server...")

        do {
            // Connect WSS
            let channel = WSSChannel()
            channel.delegate = self
            try await channel.connect(to: config.signalingServerUrl)
            wssChannel = channel

            logSIP(direction: .info, message: "Connected to \(config.signalingServerUrl)")

            // Start registration
            let agent = SIPRegistrationAgent(config: config, wssChannel: channel, transactionManager: transactionManager)
            agent.delegate = self
            registrationAgent = agent
            agent.register()

        } catch {
            updateRegistration(.failed, message: "Connection failed: \(error.localizedDescription)")
            logSIP(direction: .info, message: "Connection failed: \(error.localizedDescription)")
        }
    }

    func unregister() {
        registrationAgent?.unregister()
        registrationAgent?.stop()
        registrationAgent = nil
        wssChannel?.disconnect()
        wssChannel = nil
        transactionManager.removeAll()
        updateRegistration(.unregistered, message: "Unregistered")
    }

    // MARK: - Outgoing Call

    func initiateCall(to remoteParty: String) async {
        guard isRegistered else { return }
        guard !hasActiveCall else { return }
        guard PhoneNumberValidator.isValid(remoteParty) else { return }

        let session = CallSession(remoteParty: remoteParty, state: .initiating)
        updateCall(session)

        // Setup RTP
        let rtpPort = RTPSession.findAvailablePort()
        let rtp = RTPSession()
        rtp.delegate = self
        rtp.configure(codec: config.audioCodec)
        rtpSession = rtp

        do {
            try rtp.start(localPort: rtpPort)
        } catch {
            updateCallState(.failed, reason: "RTP setup failed: \(error.localizedDescription)")
            return
        }

        // STUN binding for NAT traversal
        if !config.stunServer.isEmpty {
            do {
                let stunResult = try await STUNClient.discoverPublicAddress(stunServer: config.stunServer, localPort: rtpPort)
                DispatchQueue.main.async {
                    self.publicIPAddress = stunResult.publicIP
                    self.config.publicIPAddress = stunResult.publicIP
                }
                logRTP("STUN: Public address \(stunResult.publicIP):\(stunResult.publicPort)")
            } catch {
                logRTP("STUN failed: \(error.localizedDescription), using local address")
            }
        }

        // Setup SIP user agent
        let ua = SIPUserAgent(config: config, wssChannel: wssChannel!, transactionManager: transactionManager)
        ua.delegate = self
        userAgent = ua

        // Report to CallKit
        callKitManager.reportOutgoingCall(to: remoteParty)

        // Initiate call
        ua.initiateCall(to: remoteParty, localRTPPort: Int(rtpPort))
    }

    // MARK: - Answer Incoming Call

    func answerCall() async {
        guard let call = currentCall, call.state == .ringing, call.isIncoming else { return }

        // Setup RTP
        let rtpPort = RTPSession.findAvailablePort()
        let rtp = RTPSession()
        rtp.delegate = self
        rtp.configure(codec: config.audioCodec)
        rtpSession = rtp

        do {
            try rtp.start(localPort: rtpPort)
        } catch {
            updateCallState(.failed, reason: "RTP setup failed")
            return
        }

        userAgent?.answerCall(localRTPPort: Int(rtpPort))
    }

    func rejectCall() {
        userAgent?.rejectCall()
        callKitManager.reportCallEnded(reason: .declinedElsewhere)
        cleanupCall()
    }

    // MARK: - End Call

    func endCall() {
        guard hasActiveCall else { return }

        if let call = currentCall {
            if call.state == .initiating || call.state == .ringing {
                if !call.isIncoming {
                    userAgent?.cancelCall()
                } else {
                    userAgent?.rejectCall()
                }
            } else {
                userAgent?.endCall()
            }
        }

        callKitManager.endCall()
        cleanupCall()
    }

    // MARK: - Hold

    func holdCall() {
        guard currentCall?.state == .connected else { return }
        rtpSession?.mute()
        updateCallState(.onHold, reason: nil)
        callKitManager.setHeld(true)
    }

    func unholdCall() {
        guard currentCall?.state == .onHold else { return }
        rtpSession?.unmute()
        updateCallState(.connected, reason: nil)
        callKitManager.setHeld(false)
    }

    // MARK: - Mute

    func muteMicrophone() {
        rtpSession?.mute()
        isMuted = true
        callKitManager.setMuted(true)
    }

    func unmuteMicrophone() {
        rtpSession?.unmute()
        isMuted = false
        callKitManager.setMuted(false)
    }

    // MARK: - Speaker

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        audioService?.enableSpeaker(isSpeakerOn)
    }

    // MARK: - DTMF

    func sendDTMF(_ digit: Character) {
        guard hasActiveCall else { return }
        // Send via RTP (RFC 2833)
        rtpSession?.sendDTMF(digit: digit)
        // Also send via SIP INFO as fallback
        userAgent?.sendDTMFInfo(digit: digit)
        logRTP("DTMF sent: \(digit)")
    }

    // MARK: - Call Duration

    func getCallDuration() -> TimeInterval {
        guard let start = callStartTime, hasActiveCall else { return 0 }
        return Date().timeIntervalSince(start)
    }

    func getRTPStats() -> (sent: Int, received: Int, bytesSent: Int, bytesReceived: Int) {
        guard let rtp = rtpSession else { return (0, 0, 0, 0) }
        return (rtp.packetsSent, rtp.packetsReceived, rtp.bytesSent, rtp.bytesReceived)
    }

    // MARK: - Private helpers

    private func updateRegistration(_ state: RegistrationState, message: String) {
        DispatchQueue.main.async {
            self.registrationState = state
            self.registrationMessage = message
        }
    }

    private func updateCall(_ session: CallSession?) {
        DispatchQueue.main.async {
            self.currentCall = session
        }
    }

    private func updateCallState(_ state: CallState, reason: String?) {
        DispatchQueue.main.async {
            self.currentCall?.state = state
            if let reason = reason {
                self.currentCall?.errorMessage = reason
            }
            if state == .connected {
                self.callStartTime = Date()
            }
        }
    }

    private func cleanupCall() {
        audioService?.stop()
        audioService = nil
        rtpSession?.stop()
        rtpSession = nil
        userAgent?.reset()
        userAgent = nil

        DispatchQueue.main.async {
            if let call = self.currentCall {
                call.endTime = Date()
                if call.state != .failed {
                    call.state = .ended
                }
            }
            self.callStartTime = nil
            self.micLevel = 0
            self.speakerLevel = 0
            self.isMuted = false
            self.isSpeakerOn = false
        }
    }

    private func startAudio() {
        let audio = AudioService(codec: config.audioCodec)
        audio.delegate = self
        audioService = audio

        do {
            try audio.start()
            logRTP("Audio engine started")
        } catch {
            logRTP("Audio start failed: \(error.localizedDescription)")
        }
    }

    private func discoverLocalIP() {
        var address: String = "0.0.0.0"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "pdp_ip0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }

        config.localIPAddress = address
        Log.app.info("Local IP: \(address)")
    }

    // MARK: - Logging

    func logSIP(direction: SIPLogDirection, message: String) {
        let entry = SIPLogEntry(direction: direction, message: message, timestamp: Date())
        DispatchQueue.main.async {
            self.sipLog.append(entry)
            if self.sipLog.count > self.sipLogMaxCount {
                self.sipLog.removeFirst()
            }
        }
    }

    func logRTP(_ message: String) {
        let timestamped = "[\(formatTimestamp(Date()))] \(message)"
        DispatchQueue.main.async {
            self.rtpLog.append(timestamped)
            if self.rtpLog.count > self.rtpLogMaxCount {
                self.rtpLog.removeFirst()
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// MARK: - WSSChannelDelegate

extension SIPService: WSSChannelDelegate {
    func wssChannel(_ channel: WSSChannel, didReceiveMessage message: String) {
        guard let sipMessage = SIPMessage.parse(message) else {
            Log.sip.warning("Failed to parse SIP message")
            return
        }

        logSIP(direction: .incoming, message: message)

        switch sipMessage.type {
        case .response:
            // Route to registration agent or user agent
            if let cseq = sipMessage.cseq {
                if cseq.method == "REGISTER" {
                    registrationAgent?.handleResponse(sipMessage)
                } else {
                    userAgent?.handleResponse(sipMessage)
                }
            }
        case .request:
            guard let method = sipMessage.method else { return }
            switch method {
            case "INVITE":
                if hasActiveCall {
                    // Busy
                    let busy = SIPMessage.createResponse(statusCode: 486, forRequest: sipMessage)
                    Task { try? await channel.send(busy.serialize()) }
                } else {
                    handleIncomingInvite(sipMessage)
                }
            case "BYE", "CANCEL", "ACK":
                userAgent?.handleRequest(sipMessage)
            case "OPTIONS":
                let ok = SIPMessage.createResponse(statusCode: 200, forRequest: sipMessage)
                Task { try? await channel.send(ok.serialize()) }
            default:
                break
            }
        }
    }

    func wssChannel(_ channel: WSSChannel, didDisconnectWithError error: Error?) {
        logSIP(direction: .info, message: "WebSocket disconnected: \(error?.localizedDescription ?? "unknown")")
        if registrationState == .registered {
            updateRegistration(.failed, message: "Connection lost")
        }
    }

    func wssChannelDidConnect(_ channel: WSSChannel) {
        logSIP(direction: .info, message: "WebSocket connected")
    }

    private func handleIncomingInvite(_ request: SIPMessage) {
        let ua = SIPUserAgent(config: config, wssChannel: wssChannel!, transactionManager: transactionManager)
        ua.delegate = self
        userAgent = ua
        ua.handleIncomingInvite(request)
    }
}

// MARK: - SIPRegistrationAgentDelegate

extension SIPService: SIPRegistrationAgentDelegate {
    func registrationAgent(_ agent: SIPRegistrationAgent, didChangeState state: RegistrationState, message: String) {
        updateRegistration(state, message: message)
        logSIP(direction: .info, message: "Registration: \(message)")
    }

    func registrationAgent(_ agent: SIPRegistrationAgent, discoveredPublicIP ip: String) {
        DispatchQueue.main.async {
            self.publicIPAddress = ip
            self.config.publicIPAddress = ip
        }
        logSIP(direction: .info, message: "Public IP discovered: \(ip)")
    }
}

// MARK: - SIPUserAgentDelegate

extension SIPService: SIPUserAgentDelegate {
    func userAgent(_ ua: SIPUserAgent, didChangeCallState state: CallState, reason: String?) {
        updateCallState(state, reason: reason)

        switch state {
        case .ringing:
            if currentCall?.isIncoming == false {
                callKitManager.reportOutgoingCallConnecting()
            }
        case .connected:
            callKitManager.reportOutgoingCallConnected()
            // Send NAT pinhole packets and start audio
            rtpSession?.sendSilence(count: 5)
            startAudio()
        case .ended, .failed:
            if state == .failed {
                callKitManager.reportCallEnded(reason: .failed)
            } else {
                callKitManager.reportCallEnded(reason: .remoteEnded)
            }
            cleanupCall()
        default:
            break
        }

        logSIP(direction: .info, message: "Call state: \(state.displayString)\(reason.map { " (\($0))" } ?? "")")
    }

    func userAgent(_ ua: SIPUserAgent, didReceiveRemoteSDP sdp: SDPSession) {
        let host = sdp.remoteAudioAddress
        let port = UInt16(sdp.remoteAudioPort)
        guard port > 0 else { return }

        rtpSession?.setRemoteEndpoint(host: host, port: port)
        logRTP("Remote RTP endpoint: \(host):\(port)")
    }

    func userAgent(_ ua: SIPUserAgent, didReceiveIncomingCall session: CallSession, request: SIPMessage) {
        updateCall(session)
        callKitManager.reportIncomingCall(from: session.remoteParty) { error in
            if let error = error {
                Log.app.error("Failed to report incoming call: \(error.localizedDescription)")
            }
        }
    }

    func userAgent(_ ua: SIPUserAgent, needsSDPOffer localPort: Int) -> String {
        let address = config.publicIPAddress ?? config.localIPAddress ?? "0.0.0.0"
        return SDPSession.buildOffer(localAddress: address, localPort: localPort, codec: config.audioCodec)
    }
}

// MARK: - RTPSessionDelegate

extension SIPService: RTPSessionDelegate {
    func rtpSession(_ session: RTPSession, didReceiveAudio payload: Data, payloadType: UInt8) {
        audioService?.playAudio(encodedPayload: payload, payloadType: payloadType)
    }

    func rtpSession(_ session: RTPSession, didUpdateMicLevel level: Float) {
        DispatchQueue.main.async {
            self.micLevel = level
        }
    }

    func rtpSession(_ session: RTPSession, didUpdateSpeakerLevel level: Float) {
        DispatchQueue.main.async {
            self.speakerLevel = level
        }
    }
}

// MARK: - AudioServiceDelegate

extension SIPService: AudioServiceDelegate {
    func audioService(_ service: AudioService, didCapture encodedAudio: Data) {
        rtpSession?.sendAudio(encodedAudio)
    }
}

// MARK: - CallKitManagerDelegate

extension SIPService: CallKitManagerDelegate {
    func callKitDidAnswerCall() {
        Task { await answerCall() }
    }

    func callKitDidEndCall() {
        endCall()
    }

    func callKitDidSetHeld(_ held: Bool) {
        if held { holdCall() } else { unholdCall() }
    }

    func callKitDidSetMuted(_ muted: Bool) {
        if muted { muteMicrophone() } else { unmuteMicrophone() }
    }

    func callKitDidActivateAudioSession() {
        // Audio session activated by CallKit - safe to start audio engine
        if currentCall?.state == .connected {
            startAudio()
        }
    }

    func callKitDidDeactivateAudioSession() {
        audioService?.stop()
    }
}

// MARK: - SIP Log Types

enum SIPLogDirection {
    case incoming  // <<
    case outgoing  // >>
    case info      // [INFO]
}

struct SIPLogEntry: Identifiable {
    let id = UUID()
    let direction: SIPLogDirection
    let message: String
    let timestamp: Date

    var directionSymbol: String {
        switch direction {
        case .incoming: return "<<"
        case .outgoing: return ">>"
        case .info: return "INFO"
        }
    }

    var timestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}
