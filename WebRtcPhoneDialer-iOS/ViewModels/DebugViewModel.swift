import Foundation
import Combine

class DebugViewModel: ObservableObject {
    let sipService: SIPService
    private var cancellables = Set<AnyCancellable>()

    init(sipService: SIPService) {
        self.sipService = sipService
    }

    var registrationInfo: String {
        var lines: [String] = []
        lines.append("Status: \(sipService.registrationState.displayString)")
        lines.append("Message: \(sipService.registrationMessage)")

        let config = sipService.getConfiguration()
        lines.append("Signaling: \(config.signalingServerUrl)")
        lines.append("Username: \(config.username)")
        lines.append("STUN: \(config.stunServer)")
        lines.append("TURN: \(config.turnServer.isEmpty ? "None" : config.turnServer)")
        lines.append("Codec: \(config.audioCodec.rawValue)")
        lines.append("Public IP: \(sipService.publicIPAddress ?? "Unknown")")

        if let call = sipService.currentCall {
            lines.append("")
            lines.append("--- Active Call ---")
            lines.append("Remote: \(call.remoteParty)")
            lines.append("State: \(call.state.displayString)")
            if let error = call.errorMessage {
                lines.append("Error: \(error)")
            }
            let stats = sipService.getRTPStats()
            lines.append("RTP Sent: \(stats.sent) pkts / \(stats.bytesSent) bytes")
            lines.append("RTP Recv: \(stats.received) pkts / \(stats.bytesReceived) bytes")
        }

        return lines.joined(separator: "\n")
    }

    func clearSIPLog() {
        sipService.sipLog.removeAll()
    }

    func clearRTPLog() {
        sipService.rtpLog.removeAll()
    }
}
