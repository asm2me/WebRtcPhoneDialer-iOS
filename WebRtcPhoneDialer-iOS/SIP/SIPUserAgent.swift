import Foundation

protocol SIPUserAgentDelegate: AnyObject {
    func userAgent(_ ua: SIPUserAgent, didChangeCallState state: CallState, reason: String?)
    func userAgent(_ ua: SIPUserAgent, didReceiveRemoteSDP sdp: SDPSession)
    func userAgent(_ ua: SIPUserAgent, didReceiveIncomingCall session: CallSession, request: SIPMessage)
    func userAgent(_ ua: SIPUserAgent, needsSDPOffer localPort: Int) -> String
}

class SIPUserAgent {
    weak var delegate: SIPUserAgentDelegate?

    private let config: SIPConfiguration
    private let wssChannel: WSSChannel
    private let transactionManager: SIPTransactionManager

    // Dialog state
    private(set) var callID: String?
    private var localTag: String = ""
    private var remoteTag: String = ""
    private var cseqNumber: Int = 0
    private var routeSet: [String] = []

    // Incoming call state
    private var pendingInviteRequest: SIPMessage?

    // Auth challenge state
    private var lastChallenge: SIPDigestChallenge?
    private var pendingSDPOffer: String?
    private var pendingRequestURI: SIPURI?

    private let queue = DispatchQueue(label: "com.webrtcphonedialer.useragent", qos: .userInteractive)

    init(config: SIPConfiguration, wssChannel: WSSChannel, transactionManager: SIPTransactionManager) {
        self.config = config
        self.wssChannel = wssChannel
        self.transactionManager = transactionManager
    }

    // MARK: - Outgoing Call

    func initiateCall(to remoteParty: String, localRTPPort: Int) {
        guard let requestURI = SIPURI.parseRelaxed(remoteParty, defaultDomain: config.sipDomain) else {
            delegate?.userAgent(self, didChangeCallState: .failed, reason: "Invalid remote party")
            return
        }

        callID = SIPMessage.generateCallID(domain: config.sipDomain)
        localTag = SIPFromToHeader.generateTag()
        cseqNumber = 1
        pendingRequestURI = requestURI

        let sdpOffer = delegate?.userAgent(self, needsSDPOffer: localRTPPort) ?? ""
        pendingSDPOffer = sdpOffer

        sendInvite(requestURI: requestURI, sdpBody: sdpOffer, authorization: nil)
        delegate?.userAgent(self, didChangeCallState: .initiating, reason: nil)
    }

    private func sendInvite(requestURI: SIPURI, sdpBody: String, authorization: String?) {
        guard let callID = callID else { return }

        let localIP = config.localIPAddress ?? "0.0.0.0"
        let via = SIPViaHeader(host: localIP, port: 5060, transport: "WSS")
        let fromURI = SIPURI(user: config.username, host: config.sipDomain)
        let from = SIPFromToHeader(uri: fromURI, tag: localTag)
        let to = SIPFromToHeader(uri: requestURI)
        let contactURI = SIPURI(scheme: "sip", user: config.username, host: localIP, port: 5060, parameters: ["transport": "wss"])
        let contact = SIPContactHeader(uri: contactURI)

        let request = SIPMessage.createRequest(
            method: "INVITE",
            requestURI: requestURI,
            from: from,
            to: to,
            callID: callID,
            cseq: cseqNumber,
            via: via,
            contact: contact,
            body: sdpBody,
            contentType: "application/sdp"
        )

        request.setHeader("Allow", value: "INVITE, ACK, CANCEL, BYE, NOTIFY, REFER, OPTIONS")

        if let auth = authorization {
            request.setHeader("Authorization", value: auth)
        }

        let transaction = SIPTransaction(request: request)
        transaction.startTimeout(seconds: 60)
        transaction.onTimeout = { [weak self] in
            guard let self = self else { return }
            self.delegate?.userAgent(self, didChangeCallState: .failed, reason: "Call timed out")
        }
        transactionManager.add(transaction)

        Task {
            do {
                try await wssChannel.send(request.serialize())
            } catch {
                delegate?.userAgent(self, didChangeCallState: .failed, reason: "Send failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Handle Responses

    func handleResponse(_ response: SIPMessage) {
        guard let code = response.statusCode else { return }

        switch code {
        case 100:
            // Trying - no state change
            break
        case 180, 183:
            delegate?.userAgent(self, didChangeCallState: .ringing, reason: nil)
        case 200:
            handleCallAnswered(response)
        case 401, 407:
            handleInviteAuthChallenge(response, code: code)
        case 486:
            delegate?.userAgent(self, didChangeCallState: .failed, reason: "Busy")
        case 487:
            delegate?.userAgent(self, didChangeCallState: .ended, reason: "Cancelled")
        case 603:
            delegate?.userAgent(self, didChangeCallState: .failed, reason: "Declined")
        default:
            if code >= 400 {
                let reason = response.reasonPhrase ?? "Error \(code)"
                delegate?.userAgent(self, didChangeCallState: .failed, reason: reason)
            }
        }
    }

    private func handleCallAnswered(_ response: SIPMessage) {
        // Save remote tag
        if let toHeader = response.to {
            remoteTag = toHeader.tag ?? ""
        }

        // Extract route set from Record-Route headers
        routeSet = response.headerValues(for: "Record-Route")

        // Send ACK
        sendACK(for: response)

        // Parse SDP answer
        if !response.body.isEmpty, let sdp = SDPSession.parse(response.body) {
            delegate?.userAgent(self, didReceiveRemoteSDP: sdp)
        }

        delegate?.userAgent(self, didChangeCallState: .connected, reason: nil)
    }

    private func handleInviteAuthChallenge(_ response: SIPMessage, code: Int) {
        let headerName = code == 401 ? "WWW-Authenticate" : "Proxy-Authenticate"
        guard let challengeStr = response.headerValue(for: headerName),
              let challenge = SIPDigestChallenge.parse(from: challengeStr),
              let requestURI = pendingRequestURI,
              let sdpOffer = pendingSDPOffer else {
            delegate?.userAgent(self, didChangeCallState: .failed, reason: "Invalid auth challenge")
            return
        }

        // Send ACK for the failed response
        sendACK(for: response)

        let authorization = SIPAuth.buildAuthorizationHeader(
            challenge: challenge,
            method: "INVITE",
            digestURI: "\(requestURI)",
            username: config.username,
            password: config.password
        )

        cseqNumber += 1
        sendInvite(requestURI: requestURI, sdpBody: sdpOffer, authorization: authorization)
    }

    private func sendACK(for response: SIPMessage) {
        guard let callID = callID,
              let cseqHeader = response.cseq else { return }

        let localIP = config.localIPAddress ?? "0.0.0.0"
        let via = SIPViaHeader(host: localIP, port: 5060, transport: "WSS")
        let fromURI = SIPURI(user: config.username, host: config.sipDomain)
        let from = SIPFromToHeader(uri: fromURI, tag: localTag)

        var toHeader: SIPFromToHeader
        if let parsedTo = response.to {
            toHeader = parsedTo
        } else {
            toHeader = SIPFromToHeader(uri: pendingRequestURI ?? SIPURI())
        }

        let requestURI = pendingRequestURI ?? SIPURI()

        let ack = SIPMessage.createRequest(
            method: "ACK",
            requestURI: requestURI,
            from: from,
            to: toHeader,
            callID: callID,
            cseq: cseqHeader.sequenceNumber,
            via: via
        )

        Task {
            try? await wssChannel.send(ack.serialize())
        }
    }

    // MARK: - End Call

    func endCall() {
        guard let callID = callID else { return }

        cseqNumber += 1
        let localIP = config.localIPAddress ?? "0.0.0.0"
        let via = SIPViaHeader(host: localIP, port: 5060, transport: "WSS")
        let fromURI = SIPURI(user: config.username, host: config.sipDomain)
        let from = SIPFromToHeader(uri: fromURI, tag: localTag)

        let toURI = pendingRequestURI ?? SIPURI()
        var to = SIPFromToHeader(uri: toURI)
        if !remoteTag.isEmpty {
            to.tag = remoteTag
        }

        let bye = SIPMessage.createRequest(
            method: "BYE",
            requestURI: toURI,
            from: from,
            to: to,
            callID: callID,
            cseq: cseqNumber,
            via: via
        )

        // Add route set
        for route in routeSet {
            bye.addHeader("Route", value: route)
        }

        let transaction = SIPTransaction(request: bye)
        transaction.startTimeout(seconds: 32)
        transactionManager.add(transaction)

        Task {
            try? await wssChannel.send(bye.serialize())
        }

        delegate?.userAgent(self, didChangeCallState: .ended, reason: "Call ended")
    }

    func cancelCall() {
        guard let callID = callID else { return }

        cseqNumber += 1
        let localIP = config.localIPAddress ?? "0.0.0.0"
        let via = SIPViaHeader(host: localIP, port: 5060, transport: "WSS")
        let fromURI = SIPURI(user: config.username, host: config.sipDomain)
        let from = SIPFromToHeader(uri: fromURI, tag: localTag)
        let toURI = pendingRequestURI ?? SIPURI()
        let to = SIPFromToHeader(uri: toURI)

        let cancel = SIPMessage.createRequest(
            method: "CANCEL",
            requestURI: toURI,
            from: from,
            to: to,
            callID: callID,
            cseq: cseqNumber - 1, // CANCEL uses same CSeq as INVITE
            via: via
        )

        Task {
            try? await wssChannel.send(cancel.serialize())
        }

        delegate?.userAgent(self, didChangeCallState: .ended, reason: "Call cancelled")
    }

    // MARK: - Incoming Call

    func handleIncomingInvite(_ request: SIPMessage) {
        callID = request.callID
        pendingInviteRequest = request

        if let fromHeader = request.from {
            remoteTag = fromHeader.tag ?? ""
        }
        localTag = SIPFromToHeader.generateTag()

        let remoteParty = request.from?.uri.user ?? request.from?.uri.description ?? "Unknown"
        let session = CallSession(remoteParty: remoteParty, state: .ringing, isIncoming: true)

        // Send 180 Ringing
        sendResponse(statusCode: 180, forRequest: request)

        delegate?.userAgent(self, didReceiveIncomingCall: session, request: request)
        delegate?.userAgent(self, didChangeCallState: .ringing, reason: nil)
    }

    func answerCall(localRTPPort: Int) {
        guard let request = pendingInviteRequest else { return }

        let sdpBody = delegate?.userAgent(self, needsSDPOffer: localRTPPort) ?? ""

        let localIP = config.localIPAddress ?? "0.0.0.0"
        let contactURI = SIPURI(scheme: "sip", user: config.username, host: localIP, port: 5060, parameters: ["transport": "wss"])
        let contact = SIPContactHeader(uri: contactURI)

        let response = SIPMessage.createResponse(
            statusCode: 200,
            forRequest: request,
            contact: contact,
            body: sdpBody,
            contentType: "application/sdp"
        )

        Task {
            try? await wssChannel.send(response.serialize())
        }

        // Parse remote SDP from the INVITE
        if !request.body.isEmpty, let sdp = SDPSession.parse(request.body) {
            delegate?.userAgent(self, didReceiveRemoteSDP: sdp)
        }

        delegate?.userAgent(self, didChangeCallState: .connected, reason: nil)
        pendingInviteRequest = nil
    }

    func rejectCall() {
        guard let request = pendingInviteRequest else { return }

        sendResponse(statusCode: 603, forRequest: request)
        delegate?.userAgent(self, didChangeCallState: .ended, reason: "Call rejected")
        pendingInviteRequest = nil
    }

    // MARK: - Handle in-dialog requests

    func handleRequest(_ request: SIPMessage) {
        guard let method = request.method else { return }

        switch method {
        case "BYE":
            // Remote party hung up
            sendResponse(statusCode: 200, forRequest: request)
            delegate?.userAgent(self, didChangeCallState: .ended, reason: "Remote party hung up")

        case "INVITE":
            // Re-INVITE (hold/unhold) - respond with 200 OK
            handleIncomingInvite(request)

        case "CANCEL":
            sendResponse(statusCode: 200, forRequest: request)
            if let invite = pendingInviteRequest {
                let terminated = SIPMessage.createResponse(statusCode: 487, forRequest: invite)
                Task { try? await wssChannel.send(terminated.serialize()) }
            }
            delegate?.userAgent(self, didChangeCallState: .ended, reason: "Call cancelled by remote")

        case "ACK":
            // ACK received for our 200 OK - call established
            break

        default:
            break
        }
    }

    private func sendResponse(statusCode: Int, forRequest request: SIPMessage) {
        let response = SIPMessage.createResponse(statusCode: statusCode, forRequest: request)
        Task {
            try? await wssChannel.send(response.serialize())
        }
    }

    // MARK: - DTMF

    func sendDTMFInfo(digit: Character) {
        guard let callID = callID else { return }
        cseqNumber += 1

        let localIP = config.localIPAddress ?? "0.0.0.0"
        let via = SIPViaHeader(host: localIP, port: 5060, transport: "WSS")
        let fromURI = SIPURI(user: config.username, host: config.sipDomain)
        let from = SIPFromToHeader(uri: fromURI, tag: localTag)
        let toURI = pendingRequestURI ?? SIPURI()
        var to = SIPFromToHeader(uri: toURI)
        if !remoteTag.isEmpty {
            to.tag = remoteTag
        }

        let info = SIPMessage.createRequest(
            method: "INFO",
            requestURI: toURI,
            from: from,
            to: to,
            callID: callID,
            cseq: cseqNumber,
            via: via,
            body: "Signal=\(digit)\r\nDuration=160",
            contentType: "application/dtmf-relay"
        )

        Task {
            try? await wssChannel.send(info.serialize())
        }
    }

    func reset() {
        callID = nil
        localTag = ""
        remoteTag = ""
        cseqNumber = 0
        routeSet = []
        pendingInviteRequest = nil
        lastChallenge = nil
        pendingSDPOffer = nil
        pendingRequestURI = nil
    }
}
