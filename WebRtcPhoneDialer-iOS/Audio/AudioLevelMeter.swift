import Foundation

/// Audio level calculation from G.711 payload (port of C# CalculateAudioLevel)
struct AudioLevelMeter {
    /// Calculate audio level from mu-law/A-law encoded payload
    /// Returns a value between 0.0 and 1.0
    static func calculateLevel(from payload: Data) -> Float {
        guard !payload.isEmpty else { return 0.0 }

        var peak: Int = 0
        for byte in payload {
            // Decode mu-law to get magnitude
            let inv = ~byte
            let exponent = Int((inv >> 4) & 0x07)
            let mantissa = Int(inv & 0x0F)
            let magnitude = ((mantissa << 1) + 33) << exponent

            if magnitude > peak {
                peak = magnitude
            }
        }

        // Normalize to 0.0-1.0 (max mu-law magnitude is ~8031)
        return min(Float(peak) / 8031.0, 1.0)
    }

    /// Calculate audio level from PCM16 samples
    static func calculateLevel(from samples: [Int16]) -> Float {
        guard !samples.isEmpty else { return 0.0 }

        var peak: Int = 0
        for sample in samples {
            let magnitude = abs(Int(sample))
            if magnitude > peak {
                peak = magnitude
            }
        }

        return min(Float(peak) / 32768.0, 1.0)
    }
}
