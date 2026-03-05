import Foundation

struct SIPViaHeader {
    var version: String = "SIP/2.0"
    var transport: String = "WSS"
    var host: String = ""
    var port: Int = 5060
    var branch: String
    var rport: String?
    var received: String?

    init(host: String, port: Int = 5060, transport: String = "WSS") {
        self.host = host
        self.port = port
        self.transport = transport
        self.branch = "z9hG4bK-\(UUID().uuidString.prefix(16))"
    }

    init?(parsing value: String) {
        // SIP/2.0/WSS host:port;branch=xxx;rport;received=x.x.x.x
        let parts = value.components(separatedBy: ";")
        guard !parts.isEmpty else { return nil }

        let mainPart = parts[0].trimmingCharacters(in: .whitespaces)
        let mainComponents = mainPart.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard mainComponents.count >= 2 else { return nil }

        let versionTransport = mainComponents[0]
        let vtParts = versionTransport.components(separatedBy: "/")
        if vtParts.count >= 3 {
            self.version = "\(vtParts[0])/\(vtParts[1])"
            self.transport = vtParts[2]
        }

        let hostPort = mainComponents[1]
        if let colonIdx = hostPort.lastIndex(of: ":") {
            self.host = String(hostPort[hostPort.startIndex..<colonIdx])
            self.port = Int(String(hostPort[hostPort.index(after: colonIdx)...])) ?? 5060
        } else {
            self.host = hostPort
            self.port = 5060
        }

        self.branch = ""
        for param in parts.dropFirst() {
            let trimmed = param.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("branch=") {
                self.branch = String(trimmed.dropFirst(7))
            } else if trimmed.lowercased().hasPrefix("received=") {
                self.received = String(trimmed.dropFirst(9))
            } else if trimmed.lowercased().hasPrefix("rport=") {
                self.rport = String(trimmed.dropFirst(6))
            } else if trimmed.lowercased() == "rport" {
                self.rport = ""
            }
        }
    }

    var headerValue: String {
        var result = "\(version)/\(transport) \(host):\(port);branch=\(branch);rport"
        if let received = received {
            result += ";received=\(received)"
        }
        return result
    }
}

struct SIPFromToHeader {
    var displayName: String?
    var uri: SIPURI
    var tag: String?

    init(uri: SIPURI, displayName: String? = nil, tag: String? = nil) {
        self.uri = uri
        self.displayName = displayName
        self.tag = tag
    }

    init?(parsing value: String) {
        var remaining = value.trimmingCharacters(in: .whitespaces)

        // Split off parameters (;tag=xxx)
        var tag: String?
        let parts = remaining.components(separatedBy: ";")
        remaining = parts[0]
        for param in parts.dropFirst() {
            let trimmed = param.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("tag=") {
                tag = String(trimmed.dropFirst(4))
            }
        }

        // Parse display name
        var displayName: String?
        if remaining.contains("<") {
            if let ltIdx = remaining.firstIndex(of: "<"),
               let gtIdx = remaining.firstIndex(of: ">") {
                let beforeLt = String(remaining[remaining.startIndex..<ltIdx]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !beforeLt.isEmpty {
                    displayName = beforeLt
                }
                remaining = String(remaining[remaining.index(after: ltIdx)..<gtIdx])
            }
        }

        guard let uri = SIPURI.parse(remaining) else { return nil }
        self.uri = uri
        self.displayName = displayName
        self.tag = tag
    }

    var headerValue: String {
        var result = ""
        if let name = displayName, !name.isEmpty {
            result += "\"\(name)\" "
        }
        result += "<\(uri)>"
        if let tag = tag {
            result += ";tag=\(tag)"
        }
        return result
    }

    static func generateTag() -> String {
        return String(UUID().uuidString.prefix(12).lowercased())
    }
}

struct SIPCSeqHeader {
    var sequenceNumber: Int
    var method: String

    init(sequenceNumber: Int, method: String) {
        self.sequenceNumber = sequenceNumber
        self.method = method
    }

    init?(parsing value: String) {
        let parts = value.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 2, let seq = Int(parts[0]) else { return nil }
        self.sequenceNumber = seq
        self.method = parts[1]
    }

    var headerValue: String {
        return "\(sequenceNumber) \(method)"
    }
}

struct SIPContactHeader {
    var uri: SIPURI
    var parameters: [String: String] = [:]

    init(uri: SIPURI) {
        self.uri = uri
    }

    init?(parsing value: String) {
        var remaining = value.trimmingCharacters(in: .whitespaces)

        // Strip angle brackets
        if let ltIdx = remaining.firstIndex(of: "<"),
           let gtIdx = remaining.firstIndex(of: ">") {
            remaining = String(remaining[remaining.index(after: ltIdx)..<gtIdx])
        }

        // Split off parameters
        let parts = remaining.components(separatedBy: ";")
        remaining = parts[0]
        var params: [String: String] = [:]
        for param in parts.dropFirst() {
            let kv = param.components(separatedBy: "=")
            if kv.count == 2 {
                params[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
            }
        }

        guard let uri = SIPURI.parse(remaining) else { return nil }
        self.uri = uri
        self.parameters = params
    }

    var headerValue: String {
        var result = "<\(uri)>"
        for (key, value) in parameters {
            result += ";\(key)=\(value)"
        }
        return result
    }
}
