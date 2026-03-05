import Foundation

/// RFC 2833 DTMF event sender
struct DTMFSender {
    static let payloadType: UInt8 = 101

    /// DTMF digit to event code mapping
    static func eventCode(for digit: Character) -> UInt8? {
        switch digit {
        case "0": return 0
        case "1": return 1
        case "2": return 2
        case "3": return 3
        case "4": return 4
        case "5": return 5
        case "6": return 6
        case "7": return 7
        case "8": return 8
        case "9": return 9
        case "*": return 10
        case "#": return 11
        case "A", "a": return 12
        case "B", "b": return 13
        case "C", "c": return 14
        case "D", "d": return 15
        default: return nil
        }
    }

    /// Build DTMF RTP event packets (RFC 2833)
    /// Returns array of RTP payloads (without RTP header) to send
    static func buildDTMFPackets(
        event: UInt8,
        volume: UInt8 = 10,
        durationMs: Int = 160,
        sampleRate: Int = 8000
    ) -> [DTMFPacketInfo] {
        var packets: [DTMFPacketInfo] = []
        let samplesPerMs = sampleRate / 1000
        let totalDuration = UInt16(durationMs * samplesPerMs)

        // Send 3 start packets (marker on first)
        for i in 0..<3 {
            let duration = UInt16(min(Int(totalDuration), (i + 1) * 160 * samplesPerMs / 8))
            let payload = buildEventPayload(event: event, endBit: false, volume: volume, duration: duration)
            packets.append(DTMFPacketInfo(payload: payload, marker: i == 0, isEnd: false))
        }

        // Send 3 end packets (E bit set, same duration)
        for _ in 0..<3 {
            let payload = buildEventPayload(event: event, endBit: true, volume: volume, duration: totalDuration)
            packets.append(DTMFPacketInfo(payload: payload, marker: false, isEnd: true))
        }

        return packets
    }

    /// Build a single DTMF event payload (4 bytes)
    /// Byte 0: Event code
    /// Byte 1: E(1) R(1) Volume(6)
    /// Bytes 2-3: Duration
    private static func buildEventPayload(event: UInt8, endBit: Bool, volume: UInt8, duration: UInt16) -> Data {
        var data = Data(count: 4)
        data[0] = event
        data[1] = (endBit ? 0x80 : 0x00) | (volume & 0x3F)
        data[2] = UInt8(duration >> 8)
        data[3] = UInt8(duration & 0xFF)
        return data
    }
}

struct DTMFPacketInfo {
    let payload: Data
    let marker: Bool
    let isEnd: Bool
}
