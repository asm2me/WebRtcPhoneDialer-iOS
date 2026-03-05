import Foundation
import Network

struct STUNBindingResult {
    var publicIP: String
    var publicPort: UInt16
}

class STUNClient {
    static let bindingRequest: UInt16 = 0x0001
    static let bindingResponse: UInt16 = 0x0101
    static let magicCookie: UInt32 = 0x2112A442

    /// Perform a STUN binding request to discover the public IP and port
    static func discoverPublicAddress(
        stunServer: String,
        localPort: UInt16,
        timeout: TimeInterval = 5
    ) async throws -> STUNBindingResult {
        // Parse STUN server address (stun:host:port or host:port)
        var host = stunServer
        var port: UInt16 = 3478

        if host.lowercased().hasPrefix("stun:") {
            host = String(host.dropFirst(5))
        }

        if let colonIdx = host.lastIndex(of: ":") {
            let portStr = String(host[host.index(after: colonIdx)...])
            if let parsedPort = UInt16(portStr) {
                port = parsedPort
                host = String(host[host.startIndex..<colonIdx])
            }
        }

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        let connection = NWConnection(host: nwHost, port: nwPort, using: .udp)

        return try await withCheckedThrowingContinuation { continuation in
            var completed = false

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Build and send STUN binding request
                    let request = buildBindingRequest()
                    let transactionID = Array(request[8..<20])

                    connection.send(content: request, completion: .contentProcessed({ error in
                        if let error = error {
                            if !completed {
                                completed = true
                                continuation.resume(throwing: error)
                            }
                            return
                        }

                        // Receive response
                        connection.receiveMessage { data, _, _, error in
                            defer { connection.cancel() }
                            if let error = error {
                                if !completed {
                                    completed = true
                                    continuation.resume(throwing: error)
                                }
                                return
                            }

                            guard let data = data,
                                  let result = parseBindingResponse(data, transactionID: transactionID) else {
                                if !completed {
                                    completed = true
                                    continuation.resume(throwing: STUNError.invalidResponse)
                                }
                                return
                            }

                            if !completed {
                                completed = true
                                continuation.resume(returning: result)
                            }
                        }
                    }))

                case .failed(let error):
                    if !completed {
                        completed = true
                        continuation.resume(throwing: error)
                    }

                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInteractive))

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if !completed {
                    completed = true
                    connection.cancel()
                    continuation.resume(throwing: STUNError.timeout)
                }
            }
        }
    }

    static func buildBindingRequest() -> Data {
        var data = Data(count: 20)

        // Message Type: Binding Request (0x0001)
        data[0] = 0x00
        data[1] = 0x01
        // Message Length: 0
        data[2] = 0x00
        data[3] = 0x00
        // Magic Cookie
        data[4] = UInt8((magicCookie >> 24) & 0xFF)
        data[5] = UInt8((magicCookie >> 16) & 0xFF)
        data[6] = UInt8((magicCookie >> 8) & 0xFF)
        data[7] = UInt8(magicCookie & 0xFF)
        // Transaction ID (12 random bytes)
        for i in 8..<20 {
            data[i] = UInt8.random(in: 0...255)
        }

        return data
    }

    static func parseBindingResponse(_ data: Data, transactionID: [UInt8]) -> STUNBindingResult? {
        guard data.count >= 20 else { return nil }

        // Verify message type is Binding Response
        let msgType = UInt16(data[0]) << 8 | UInt16(data[1])
        guard msgType == bindingResponse else { return nil }

        // Verify transaction ID
        for i in 0..<12 {
            guard data[8 + i] == transactionID[i] else { return nil }
        }

        let msgLength = Int(UInt16(data[2]) << 8 | UInt16(data[3]))
        guard data.count >= 20 + msgLength else { return nil }

        // Parse attributes
        var offset = 20
        while offset + 4 <= 20 + msgLength {
            let attrType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            let attrLength = Int(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]))
            offset += 4

            guard offset + attrLength <= data.count else { break }

            // XOR-MAPPED-ADDRESS (0x0020)
            if attrType == 0x0020 && attrLength >= 8 {
                let family = data[offset + 1]
                if family == 0x01 { // IPv4
                    let xPort = (UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])) ^ UInt16(magicCookie >> 16)
                    let xIP0 = data[offset + 4] ^ UInt8((magicCookie >> 24) & 0xFF)
                    let xIP1 = data[offset + 5] ^ UInt8((magicCookie >> 16) & 0xFF)
                    let xIP2 = data[offset + 6] ^ UInt8((magicCookie >> 8) & 0xFF)
                    let xIP3 = data[offset + 7] ^ UInt8(magicCookie & 0xFF)
                    return STUNBindingResult(publicIP: "\(xIP0).\(xIP1).\(xIP2).\(xIP3)", publicPort: xPort)
                }
            }

            // MAPPED-ADDRESS (0x0001) - fallback
            if attrType == 0x0001 && attrLength >= 8 {
                let family = data[offset + 1]
                if family == 0x01 { // IPv4
                    let port = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
                    let ip = "\(data[offset + 4]).\(data[offset + 5]).\(data[offset + 6]).\(data[offset + 7])"
                    return STUNBindingResult(publicIP: ip, publicPort: port)
                }
            }

            // Pad to 4-byte boundary
            offset += (attrLength + 3) & ~3
        }

        return nil
    }
}

enum STUNError: Error, LocalizedError {
    case timeout
    case invalidResponse
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .timeout: return "STUN request timed out"
        case .invalidResponse: return "Invalid STUN response"
        case .connectionFailed: return "STUN connection failed"
        }
    }
}
