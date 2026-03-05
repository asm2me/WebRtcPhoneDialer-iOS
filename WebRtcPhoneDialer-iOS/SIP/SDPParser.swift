import Foundation

struct SDPMediaDescription {
    var mediaType: String = "audio"     // audio, video
    var port: Int = 0
    var protocol_: String = "RTP/AVP"
    var payloadTypes: [Int] = []
    var rtpMap: [Int: String] = [:]     // PT -> codec/rate
    var fmtp: [Int: String] = [:]       // PT -> format params
    var direction: String = "sendrecv"
    var connectionAddress: String?
}

struct SDPSession {
    var version: Int = 0
    var origin: String = ""
    var sessionName: String = "-"
    var connectionAddress: String = ""
    var timing: String = "0 0"
    var mediaDescriptions: [SDPMediaDescription] = []

    var audioDescription: SDPMediaDescription? {
        mediaDescriptions.first(where: { $0.mediaType == "audio" })
    }

    var remoteAudioAddress: String {
        audioDescription?.connectionAddress ?? connectionAddress
    }

    var remoteAudioPort: Int {
        audioDescription?.port ?? 0
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> SDPSession? {
        var session = SDPSession()
        var currentMedia: SDPMediaDescription?

        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        for line in lines {
            guard line.count >= 2, line[line.index(line.startIndex, offsetBy: 1)] == "=" else { continue }
            let type = line[line.startIndex]
            let value = String(line.dropFirst(2))

            switch type {
            case "v":
                session.version = Int(value) ?? 0
            case "o":
                session.origin = value
            case "s":
                session.sessionName = value
            case "c":
                let addr = parseConnectionAddress(value)
                if currentMedia != nil {
                    currentMedia?.connectionAddress = addr
                } else {
                    session.connectionAddress = addr
                }
            case "t":
                session.timing = value
            case "m":
                // Save previous media
                if let media = currentMedia {
                    session.mediaDescriptions.append(media)
                }
                currentMedia = parseMediaLine(value)
            case "a":
                if currentMedia != nil {
                    parseAttribute(value, media: &currentMedia!)
                }
            default:
                break
            }
        }

        // Save last media description
        if let media = currentMedia {
            session.mediaDescriptions.append(media)
        }

        return session
    }

    private static func parseConnectionAddress(_ value: String) -> String {
        // c=IN IP4 192.168.1.100
        let parts = value.components(separatedBy: .whitespaces)
        return parts.count >= 3 ? parts[2] : ""
    }

    private static func parseMediaLine(_ value: String) -> SDPMediaDescription {
        // m=audio 10000 RTP/AVP 0 8 101
        var media = SDPMediaDescription()
        let parts = value.components(separatedBy: .whitespaces)
        if parts.count >= 3 {
            media.mediaType = parts[0]
            media.port = Int(parts[1]) ?? 0
            media.protocol_ = parts[2]
            media.payloadTypes = parts.dropFirst(3).compactMap { Int($0) }
        }
        return media
    }

    private static func parseAttribute(_ value: String, media: inout SDPMediaDescription) {
        if value.lowercased().hasPrefix("rtpmap:") {
            // a=rtpmap:0 PCMU/8000
            let content = String(value.dropFirst(7))
            let parts = content.components(separatedBy: .whitespaces)
            if parts.count >= 2, let pt = Int(parts[0]) {
                media.rtpMap[pt] = parts[1]
            }
        } else if value.lowercased().hasPrefix("fmtp:") {
            // a=fmtp:101 0-16
            let content = String(value.dropFirst(5))
            let parts = content.components(separatedBy: .whitespaces)
            if parts.count >= 2, let pt = Int(parts[0]) {
                media.fmtp[pt] = parts[1...].joined(separator: " ")
            }
        } else if ["sendrecv", "sendonly", "recvonly", "inactive"].contains(value.lowercased()) {
            media.direction = value.lowercased()
        }
    }

    // MARK: - Building

    static func buildOffer(
        localAddress: String,
        localPort: Int,
        codec: SIPConfiguration.AudioCodec,
        sessionID: UInt32? = nil
    ) -> String {
        let sid = sessionID ?? UInt32.random(in: 1...999999)
        var lines: [String] = []
        lines.append("v=0")
        lines.append("o=- \(sid) \(sid) IN IP4 \(localAddress)")
        lines.append("s=-")
        lines.append("c=IN IP4 \(localAddress)")
        lines.append("t=0 0")

        // Audio media line
        var payloadTypes = ["\(codec.payloadType)"]
        // Always include telephone-event
        payloadTypes.append("101")
        lines.append("m=audio \(localPort) RTP/AVP \(payloadTypes.joined(separator: " "))")

        // RTP map
        lines.append("a=rtpmap:\(codec.payloadType) \(codec.rtpMapString)")
        lines.append("a=rtpmap:101 telephone-event/8000")
        lines.append("a=fmtp:101 0-16")
        lines.append("a=sendrecv")
        lines.append("a=ptime:20")

        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
