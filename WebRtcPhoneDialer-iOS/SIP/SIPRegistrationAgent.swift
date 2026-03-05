import Foundation

protocol SIPRegistrationAgentDelegate: AnyObject {
    func registrationAgent(_ agent: SIPRegistrationAgent, didChangeState state: RegistrationState, message: String)
    func registrationAgent(_ agent: SIPRegistrationAgent, discoveredPublicIP ip: String)
}

class SIPRegistrationAgent {
    weak var delegate: SIPRegistrationAgentDelegate?

    private let config: SIPConfiguration
    private let wssChannel: WSSChannel
    private let transactionManager: SIPTransactionManager

    private var callID: String = ""
    private var localTag: String = ""
    private var cseqNumber: Int = 0
    private var registrationExpiry: Int = 3600
    private var reRegistrationTimer: DispatchSourceTimer?
    private var isRegistered = false
    private let queue = DispatchQueue(label: "com.webrtcphonedialer.registration")

    init(config: SIPConfiguration, wssChannel: WSSChannel, transactionManager: SIPTransactionManager) {
        self.config = config
        self.wssChannel = wssChannel
        self.transactionManager = transactionManager
        self.callID = SIPMessage.generateCallID(domain: config.sipDomain)
        self.localTag = SIPFromToHeader.generateTag()
    }

    func register() {
        delegate?.registrationAgent(self, didChangeState: .registering, message: "Registering...")
        cseqNumber += 1
        sendRegister(authorization: nil)
    }

    func unregister() {
        reRegistrationTimer?.cancel()
        reRegistrationTimer = nil

        if isRegistered {
            cseqNumber += 1
            sendRegister(authorization: nil, expires: 0)
        }

        isRegistered = false
        delegate?.registrationAgent(self, didChangeState: .unregistered, message: "Unregistered")
    }

    func handleResponse(_ response: SIPMessage) {
        guard let code = response.statusCode else { return }

        switch code {
        case 200:
            handleSuccess(response)
        case 401, 407:
            handleAuthChallenge(response, code: code)
        default:
            handleFailure(response)
        }
    }

    private func sendRegister(authorization: String?, expires: Int? = nil) {
        let domain = config.sipDomain
        guard let requestURI = SIPURI.parse("sip:\(domain)") else {
            delegate?.registrationAgent(self, didChangeState: .failed, message: "Invalid SIP domain")
            return
        }

        let localIP = config.localIPAddress ?? "0.0.0.0"
        let via = SIPViaHeader(host: localIP, port: 5060, transport: "WSS")
        let fromURI = SIPURI(user: config.username, host: domain)
        let from = SIPFromToHeader(uri: fromURI, tag: localTag)
        let to = SIPFromToHeader(uri: fromURI)
        let contactURI = SIPURI(scheme: "sip", user: config.username, host: localIP, port: 5060, parameters: ["transport": "wss"])
        let contact = SIPContactHeader(uri: contactURI)

        let request = SIPMessage.createRequest(
            method: "REGISTER",
            requestURI: requestURI,
            from: from,
            to: to,
            callID: callID,
            cseq: cseqNumber,
            via: via,
            contact: contact
        )

        let exp = expires ?? registrationExpiry
        request.setHeader("Expires", value: "\(exp)")

        if let auth = authorization {
            request.setHeader("Authorization", value: auth)
        }

        let transaction = SIPTransaction(request: request)
        transaction.startTimeout(seconds: 32)
        transaction.onTimeout = { [weak self] in
            guard let self = self else { return }
            self.delegate?.registrationAgent(self, didChangeState: .failed, message: "Registration timed out")
        }
        transactionManager.add(transaction)

        Task {
            do {
                try await wssChannel.send(request.serialize())
            } catch {
                delegate?.registrationAgent(self, didChangeState: .failed, message: "Send failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleSuccess(_ response: SIPMessage) {
        isRegistered = true

        // Extract public IP from Via received parameter
        if let via = response.via, let received = via.received {
            delegate?.registrationAgent(self, discoveredPublicIP: received)
        }

        // Extract expiry
        if let expiresStr = response.headerValue(for: "Expires"),
           let expires = Int(expiresStr), expires > 0 {
            registrationExpiry = expires
        }

        let message = "Registered as sip:\(config.username)@\(config.sipDomain)"
        delegate?.registrationAgent(self, didChangeState: .registered, message: message)

        // Schedule re-registration at 80% of expiry
        scheduleReRegistration()
    }

    private func handleAuthChallenge(_ response: SIPMessage, code: Int) {
        let headerName = code == 401 ? "WWW-Authenticate" : "Proxy-Authenticate"
        guard let challengeStr = response.headerValue(for: headerName),
              let challenge = SIPDigestChallenge.parse(from: challengeStr) else {
            delegate?.registrationAgent(self, didChangeState: .failed, message: "Invalid auth challenge")
            return
        }

        let digestURI = "sip:\(config.sipDomain)"
        let authorization = SIPAuth.buildAuthorizationHeader(
            challenge: challenge,
            method: "REGISTER",
            digestURI: digestURI,
            username: config.username,
            password: config.password
        )

        cseqNumber += 1
        sendRegister(authorization: authorization)
    }

    private func handleFailure(_ response: SIPMessage) {
        let code = response.statusCode ?? 0
        let reason = response.reasonPhrase ?? "Unknown error"
        isRegistered = false
        delegate?.registrationAgent(self, didChangeState: .failed, message: "\(code) \(reason)")
    }

    private func scheduleReRegistration() {
        reRegistrationTimer?.cancel()

        let interval = Double(registrationExpiry) * 0.8
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.cseqNumber += 1
            self.sendRegister(authorization: nil)
        }
        timer.resume()
        reRegistrationTimer = timer
    }

    func stop() {
        reRegistrationTimer?.cancel()
        reRegistrationTimer = nil
        isRegistered = false
    }
}
