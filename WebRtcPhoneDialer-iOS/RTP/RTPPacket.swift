import Foundation

struct RTPPacket {
    static let headerSize = 12

    var version: UInt8 = 2
    var padding: Bool = false
    var extension_: Bool = false
    var csrcCount: UInt8 = 0
    var marker: Bool = false
    var payloadType: UInt8 = 0
    var sequenceNumber: UInt16 = 0
    var timestamp: UInt32 = 0
    var ssrc: UInt32 = 0
    var payload: Data = Data()

    // MARK: - Build

    func serialize() -> Data {
        var data = Data(count: RTPPacket.headerSize + payload.count)

        // Byte 0: V(2) P(1) X(1) CC(4)
        var byte0: UInt8 = (version & 0x03) << 6
        if padding { byte0 |= 0x20 }
        if extension_ { byte0 |= 0x10 }
        byte0 |= (csrcCount & 0x0F)
        data[0] = byte0

        // Byte 1: M(1) PT(7)
        var byte1: UInt8 = payloadType & 0x7F
        if marker { byte1 |= 0x80 }
        data[1] = byte1

        // Bytes 2-3: Sequence number
        data[2] = UInt8(sequenceNumber >> 8)
        data[3] = UInt8(sequenceNumber & 0xFF)

        // Bytes 4-7: Timestamp
        data[4] = UInt8((timestamp >> 24) & 0xFF)
        data[5] = UInt8((timestamp >> 16) & 0xFF)
        data[6] = UInt8((timestamp >> 8) & 0xFF)
        data[7] = UInt8(timestamp & 0xFF)

        // Bytes 8-11: SSRC
        data[8] = UInt8((ssrc >> 24) & 0xFF)
        data[9] = UInt8((ssrc >> 16) & 0xFF)
        data[10] = UInt8((ssrc >> 8) & 0xFF)
        data[11] = UInt8(ssrc & 0xFF)

        // Payload
        if !payload.isEmpty {
            data.replaceSubrange(RTPPacket.headerSize..<(RTPPacket.headerSize + payload.count), with: payload)
        }

        return data
    }

    // MARK: - Parse

    static func parse(_ data: Data) -> RTPPacket? {
        guard data.count >= headerSize else { return nil }

        var packet = RTPPacket()

        let byte0 = data[0]
        packet.version = (byte0 >> 6) & 0x03
        packet.padding = (byte0 & 0x20) != 0
        packet.extension_ = (byte0 & 0x10) != 0
        packet.csrcCount = byte0 & 0x0F

        guard packet.version == 2 else { return nil }

        let byte1 = data[1]
        packet.marker = (byte1 & 0x80) != 0
        packet.payloadType = byte1 & 0x7F

        packet.sequenceNumber = UInt16(data[2]) << 8 | UInt16(data[3])

        packet.timestamp = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 |
                           UInt32(data[6]) << 8 | UInt32(data[7])

        packet.ssrc = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 |
                      UInt32(data[10]) << 8 | UInt32(data[11])

        let payloadOffset = headerSize + Int(packet.csrcCount) * 4
        if payloadOffset < data.count {
            packet.payload = data.subdata(in: payloadOffset..<data.count)
        }

        return packet
    }
}
