import Foundation

/// G.711 mu-law codec (PCMU, payload type 0)
struct PCMUCodec {
    static let payloadType: UInt8 = 0
    static let sampleRate: Int = 8000
    static let samplesPerFrame: Int = 160 // 20ms at 8kHz

    // Mu-law encoding table
    private static let muLawCompressTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 65536)
        for i in 0..<65536 {
            let sample = Int16(bitPattern: UInt16(i))
            table[i] = encodeSample(sample)
        }
        return table
    }()

    // Mu-law decoding table
    static let muLawDecompressTable: [Int16] = {
        var table = [Int16](repeating: 0, count: 256)
        for i in 0..<256 {
            table[i] = decodeSample(UInt8(i))
        }
        return table
    }()

    static func encode(pcm: [Int16]) -> Data {
        var encoded = Data(count: pcm.count)
        for i in 0..<pcm.count {
            let index = Int(bitPattern: UInt(UInt16(bitPattern: pcm[i])))
            encoded[i] = muLawCompressTable[index]
        }
        return encoded
    }

    static func decode(mulaw: Data) -> [Int16] {
        var decoded = [Int16](repeating: 0, count: mulaw.count)
        for i in 0..<mulaw.count {
            decoded[i] = muLawDecompressTable[Int(mulaw[i])]
        }
        return decoded
    }

    private static func encodeSample(_ sample: Int16) -> UInt8 {
        let MULAW_MAX: Int32 = 0x1FFF
        let MULAW_BIAS: Int32 = 33

        var pcm = Int32(sample)
        let sign: UInt8 = pcm < 0 ? 0x80 : 0

        if pcm < 0 { pcm = -pcm }
        if pcm > MULAW_MAX { pcm = MULAW_MAX }

        pcm += MULAW_BIAS

        var exponent: UInt8 = 7
        let exponentMask: Int32 = 0x4000
        var shifted = exponentMask
        while exponent > 0 {
            if pcm >= shifted { break }
            exponent -= 1
            shifted >>= 1
        }

        let mantissa = UInt8((pcm >> (Int(exponent) + 3)) & 0x0F)
        let mulaw = ~(sign | (exponent << 4) | mantissa)
        return mulaw
    }

    private static func decodeSample(_ mulaw: UInt8) -> Int16 {
        let inv = ~mulaw
        let sign = inv & 0x80
        let exponent = Int((inv >> 4) & 0x07)
        let mantissa = Int(inv & 0x0F)

        var magnitude = ((mantissa << 1) + 33) << exponent
        magnitude -= 33

        return sign != 0 ? Int16(-magnitude) : Int16(magnitude)
    }

    /// Generate silence frame (160 samples of mu-law silence = 0xFF)
    static func silenceFrame() -> Data {
        return Data(repeating: 0xFF, count: samplesPerFrame)
    }
}
