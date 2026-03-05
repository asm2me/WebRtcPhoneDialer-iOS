import Foundation
import Network

protocol RTPSessionDelegate: AnyObject {
    func rtpSession(_ session: RTPSession, didReceiveAudio payload: Data, payloadType: UInt8)
    func rtpSession(_ session: RTPSession, didUpdateMicLevel level: Float)
    func rtpSession(_ session: RTPSession, didUpdateSpeakerLevel level: Float)
}

class RTPSession {
    weak var delegate: RTPSessionDelegate?

    private var connection: NWConnection?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.webrtcphonedialer.rtp", qos: .userInteractive)

    private(set) var localPort: UInt16 = 0
    private var remoteHost: String = ""
    private var remotePort: UInt16 = 0

    private var ssrc: UInt32 = UInt32.random(in: 1...UInt32.max)
    private var sequenceNumber: UInt16 = UInt16.random(in: 0...UInt16.max)
    private var timestamp: UInt32 = UInt32.random(in: 0...UInt32.max)
    private var payloadType: UInt8 = 0

    private var isActive = false
    private var isMuted = false

    // Statistics
    private(set) var packetsSent: Int = 0
    private(set) var packetsReceived: Int = 0
    private(set) var bytesSent: Int = 0
    private(set) var bytesReceived: Int = 0

    // Audio level throttling
    private var lastMicLevelUpdate: Date = .distantPast
    private var lastSpeakerLevelUpdate: Date = .distantPast
    private let levelUpdateInterval: TimeInterval = 1.0 / 20.0 // 20 fps

    // MARK: - Setup

    func configure(codec: SIPConfiguration.AudioCodec) {
        self.payloadType = codec.payloadType
    }

    func start(localPort: UInt16) throws {
        self.localPort = localPort

        // Create UDP listener on local port
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.any), port: NWEndpoint.Port(rawValue: localPort)!)

        listener = try NWListener(using: params)
        listener?.stateUpdateHandler = { state in
            Log.rtp.info("RTP listener state: \(String(describing: state))")
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingConnection(connection)
        }
        listener?.start(queue: queue)
        isActive = true

        Log.rtp.info("RTP session started on port \(localPort)")
    }

    func setRemoteEndpoint(host: String, port: UInt16) {
        self.remoteHost = host
        self.remotePort = port

        // Create outgoing UDP connection
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        connection = NWConnection(host: nwHost, port: nwPort, using: .udp)
        connection?.stateUpdateHandler = { state in
            Log.rtp.info("RTP connection state: \(String(describing: state))")
        }
        connection?.start(queue: queue)

        Log.rtp.info("RTP remote endpoint set to \(host):\(port)")
    }

    // MARK: - Send

    func sendAudio(_ encodedPayload: Data) {
        guard isActive, !isMuted, let connection = connection else { return }

        var packet = RTPPacket()
        packet.payloadType = payloadType
        packet.sequenceNumber = sequenceNumber
        packet.timestamp = timestamp
        packet.ssrc = ssrc
        packet.payload = encodedPayload

        let data = packet.serialize()
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                Log.rtp.error("RTP send error: \(error.localizedDescription)")
            }
        }))

        sequenceNumber &+= 1
        timestamp &+= UInt32(PCMUCodec.samplesPerFrame) // 160 samples per 20ms frame
        packetsSent += 1
        bytesSent += data.count

        // Update mic level
        updateMicLevel(from: encodedPayload)
    }

    func sendSilence(count: Int = 5) {
        let silence = PCMUCodec.silenceFrame()
        for _ in 0..<count {
            var packet = RTPPacket()
            packet.payloadType = payloadType
            packet.sequenceNumber = sequenceNumber
            packet.timestamp = timestamp
            packet.ssrc = ssrc
            packet.payload = silence

            let data = packet.serialize()
            connection?.send(content: data, completion: .contentProcessed({ _ in }))
            sequenceNumber &+= 1
            timestamp &+= UInt32(PCMUCodec.samplesPerFrame)
        }
        Log.rtp.info("Sent \(count) NAT pinhole silence packets")
    }

    // MARK: - DTMF

    func sendDTMF(digit: Character) {
        guard let event = DTMFSender.eventCode(for: digit) else { return }

        let packets = DTMFSender.buildDTMFPackets(event: event)
        let dtmfTimestamp = timestamp

        for (index, info) in packets.enumerated() {
            var rtpPacket = RTPPacket()
            rtpPacket.payloadType = DTMFSender.payloadType
            rtpPacket.sequenceNumber = sequenceNumber &+ UInt16(index)
            rtpPacket.timestamp = dtmfTimestamp // Same timestamp for entire event
            rtpPacket.ssrc = ssrc
            rtpPacket.marker = info.marker
            rtpPacket.payload = info.payload

            let data = rtpPacket.serialize()
            connection?.send(content: data, completion: .contentProcessed({ _ in }))
        }

        sequenceNumber &+= UInt16(packets.count)
        Log.rtp.info("Sent DTMF digit: \(digit)")
    }

    // MARK: - Mute

    func mute() { isMuted = true }
    func unmute() { isMuted = false }

    // MARK: - Stop

    func stop() {
        isActive = false
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
        Log.rtp.info("RTP session stopped. Sent: \(packetsSent) packets, Received: \(packetsReceived) packets")
    }

    // MARK: - Private

    private func handleIncomingConnection(_ incomingConnection: NWConnection) {
        incomingConnection.start(queue: queue)
        receiveData(from: incomingConnection)
    }

    private func receiveData(from connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, self.isActive else { return }

            if let data = data, let packet = RTPPacket.parse(data) {
                self.packetsReceived += 1
                self.bytesReceived += data.count

                if packet.payloadType == DTMFSender.payloadType {
                    // DTMF event - ignore for now
                } else {
                    self.delegate?.rtpSession(self, didReceiveAudio: packet.payload, payloadType: packet.payloadType)
                    self.updateSpeakerLevel(from: packet.payload)
                }
            }

            // Continue receiving
            self.receiveData(from: connection)
        }
    }

    private func updateMicLevel(from payload: Data) {
        let now = Date()
        guard now.timeIntervalSince(lastMicLevelUpdate) >= levelUpdateInterval else { return }
        lastMicLevelUpdate = now
        let level = AudioLevelMeter.calculateLevel(from: payload)
        delegate?.rtpSession(self, didUpdateMicLevel: level)
    }

    private func updateSpeakerLevel(from payload: Data) {
        let now = Date()
        guard now.timeIntervalSince(lastSpeakerLevelUpdate) >= levelUpdateInterval else { return }
        lastSpeakerLevelUpdate = now
        let level = AudioLevelMeter.calculateLevel(from: payload)
        delegate?.rtpSession(self, didUpdateSpeakerLevel: level)
    }

    /// Find an available local UDP port
    static func findAvailablePort(startingFrom basePort: UInt16 = 10000) -> UInt16 {
        for port in stride(from: basePort, to: 65000, by: 2) {
            // Even ports for RTP (odd for RTCP)
            let params = NWParameters.udp
            if let testListener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) {
                testListener.cancel()
                return port
            }
        }
        return basePort
    }
}
