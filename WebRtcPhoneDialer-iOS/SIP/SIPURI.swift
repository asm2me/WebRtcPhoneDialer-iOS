import Foundation

struct SIPURI: CustomStringConvertible {
    var scheme: String = "sip"
    var user: String = ""
    var host: String = ""
    var port: Int?
    var parameters: [String: String] = [:]

    var description: String {
        var result = "\(scheme):"
        if !user.isEmpty {
            result += "\(user)@"
        }
        result += host
        if let port = port {
            result += ":\(port)"
        }
        for (key, value) in parameters {
            result += ";\(key)=\(value)"
        }
        return result
    }

    var hostPort: String {
        if let port = port {
            return "\(host):\(port)"
        }
        return host
    }

    static func parse(_ input: String) -> SIPURI? {
        var uri = SIPURI()
        var remaining = input.trimmingCharacters(in: .whitespaces)

        // Parse scheme
        if let colonIndex = remaining.firstIndex(of: ":") {
            let scheme = String(remaining[remaining.startIndex..<colonIndex]).lowercased()
            if scheme == "sip" || scheme == "sips" {
                uri.scheme = scheme
                remaining = String(remaining[remaining.index(after: colonIndex)...])
            }
        }

        // Split off parameters
        let paramParts = remaining.components(separatedBy: ";")
        remaining = paramParts[0]
        for paramPart in paramParts.dropFirst() {
            let kv = paramPart.components(separatedBy: "=")
            if kv.count == 2 {
                uri.parameters[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
            }
        }

        // Parse user@host:port
        if let atIndex = remaining.lastIndex(of: "@") {
            uri.user = String(remaining[remaining.startIndex..<atIndex])
            remaining = String(remaining[remaining.index(after: atIndex)...])
        }

        // Parse host:port
        // Handle IPv6 addresses in brackets
        if remaining.hasPrefix("[") {
            if let closeBracket = remaining.firstIndex(of: "]") {
                uri.host = String(remaining[remaining.startIndex...closeBracket])
                remaining = String(remaining[remaining.index(after: closeBracket)...])
                if remaining.hasPrefix(":") {
                    remaining.removeFirst()
                    uri.port = Int(remaining)
                }
            }
        } else if let colonIndex = remaining.lastIndex(of: ":") {
            uri.host = String(remaining[remaining.startIndex..<colonIndex])
            let portStr = String(remaining[remaining.index(after: colonIndex)...])
            uri.port = Int(portStr)
        } else {
            uri.host = remaining
        }

        guard !uri.host.isEmpty else { return nil }
        return uri
    }

    /// Parse a relaxed input (phone number or SIP URI)
    static func parseRelaxed(_ input: String, defaultDomain: String) -> SIPURI? {
        if input.lowercased().hasPrefix("sip:") || input.lowercased().hasPrefix("sips:") {
            return parse(input)
        }
        if input.contains("@") {
            return parse("sip:\(input)")
        }
        // Treat as phone number
        let digits = input.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
        guard !digits.isEmpty else { return nil }
        var uri = SIPURI()
        uri.user = digits
        uri.host = defaultDomain
        return uri
    }
}
