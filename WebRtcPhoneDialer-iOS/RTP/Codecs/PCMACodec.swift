import Foundation

/// G.711 A-law codec (PCMA, payload type 8)
struct PCMACodec {
    static let payloadType: UInt8 = 8
    static let sampleRate: Int = 8000
    static let samplesPerFrame: Int = 160 // 20ms at 8kHz

    // A-law decoding table
    static let aLawDecompressTable: [Int16] = {
        var table = [Int16](repeating: 0, count: 256)
        for i in 0..<256 {
            table[i] = decodeSample(UInt8(i))
        }
        return table
    }()

    static func encode(pcm: [Int16]) -> Data {
        var encoded = Data(count: pcm.count)
        for i in 0..<pcm.count {
            encoded[i] = encodeSample(pcm[i])
        }
        return encoded
    }

    static func decode(alaw: Data) -> [Int16] {
        var decoded = [Int16](repeating: 0, count: alaw.count)
        for i in 0..<alaw.count {
            decoded[i] = aLawDecompressTable[Int(alaw[i])]
        }
        return decoded
    }

    private static func encodeSample(_ sample: Int16) -> UInt8 {
        var pcm = Int32(sample)
        let sign: UInt8

        if pcm >= 0 {
            sign = 0xD5
        } else {
            sign = 0x55
            pcm = -pcm
        }

        if pcm > 32767 { pcm = 32767 }

        var exponent: UInt8 = 7
        var mask: Int32 = 0x4000
        while exponent > 0 {
            if pcm >= mask { break }
            exponent -= 1
            mask >>= 1
        }

        let mantissa: UInt8
        if exponent == 0 {
            mantissa = UInt8((pcm >> 4) & 0x0F)
        } else {
            mantissa = UInt8((pcm >> (Int(exponent) + 3)) & 0x0F)
        }

        let alaw = (sign & 0x80) | (exponent << 4) | mantissa
        return alaw ^ 0xD5
    }

    private static func decodeSample(_ alaw: UInt8) -> Int16 {
        let input = alaw ^ 0x55
        let sign = input & 0x80
        let exponent = Int((input >> 4) & 0x07)
        let mantissa = Int(input & 0x0F)

        var magnitude: Int
        if exponent == 0 {
            magnitude = (mantissa << 4) + 8
        } else {
            magnitude = ((mantissa << 1) + 33) << (exponent + 2)
        }

        return sign != 0 ? Int16(-magnitude) : Int16(magnitude)
    }

    /// Generate silence frame
    static func silenceFrame() -> Data {
        return Data(repeating: 0xD5, count: samplesPerFrame) // A-law silence
    }
}
