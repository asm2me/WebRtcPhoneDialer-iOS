import Foundation
import CryptoKit

struct SIPDigestChallenge {
    var realm: String = ""
    var nonce: String = ""
    var algorithm: String = "MD5"
    var qop: String?
    var opaque: String?

    static func parse(from headerValue: String) -> SIPDigestChallenge? {
        guard headerValue.lowercased().hasPrefix("digest") else { return nil }
        let paramString = String(headerValue.dropFirst(6)).trimmingCharacters(in: .whitespaces)

        var challenge = SIPDigestChallenge()

        // Parse comma-separated key=value pairs
        let params = splitDigestParams(paramString)
        for (key, value) in params {
            let strippedValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key.lowercased() {
            case "realm": challenge.realm = strippedValue
            case "nonce": challenge.nonce = strippedValue
            case "algorithm": challenge.algorithm = strippedValue
            case "qop": challenge.qop = strippedValue
            case "opaque": challenge.opaque = strippedValue
            default: break
            }
        }

        guard !challenge.realm.isEmpty && !challenge.nonce.isEmpty else { return nil }
        return challenge
    }

    private static func splitDigestParams(_ input: String) -> [(String, String)] {
        var result: [(String, String)] = []
        var current = ""
        var inQuotes = false

        for char in input {
            if char == "\"" {
                inQuotes = !inQuotes
                current.append(char)
            } else if char == "," && !inQuotes {
                if let pair = parseKeyValue(current) {
                    result.append(pair)
                }
                current = ""
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty, let pair = parseKeyValue(current) {
            result.append(pair)
        }
        return result
    }

    private static func parseKeyValue(_ input: String) -> (String, String)? {
        let parts = input.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
        guard parts.count >= 2 else { return nil }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
        return (key, value)
    }
}

struct SIPAuth {
    static func buildAuthorizationHeader(
        challenge: SIPDigestChallenge,
        method: String,
        digestURI: String,
        username: String,
        password: String
    ) -> String {
        let ha1 = md5Hash("\(username):\(challenge.realm):\(password)")
        let ha2 = md5Hash("\(method):\(digestURI)")

        let response: String
        if let qop = challenge.qop, qop.contains("auth") {
            let nc = "00000001"
            let cnonce = String(UUID().uuidString.prefix(8).lowercased())
            response = md5Hash("\(ha1):\(challenge.nonce):\(nc):\(cnonce):auth:\(ha2)")

            var header = "Digest username=\"\(username)\""
            header += ", realm=\"\(challenge.realm)\""
            header += ", nonce=\"\(challenge.nonce)\""
            header += ", uri=\"\(digestURI)\""
            header += ", response=\"\(response)\""
            header += ", algorithm=\(challenge.algorithm)"
            header += ", qop=auth"
            header += ", nc=\(nc)"
            header += ", cnonce=\"\(cnonce)\""
            if let opaque = challenge.opaque {
                header += ", opaque=\"\(opaque)\""
            }
            return header
        } else {
            response = md5Hash("\(ha1):\(challenge.nonce):\(ha2)")

            var header = "Digest username=\"\(username)\""
            header += ", realm=\"\(challenge.realm)\""
            header += ", nonce=\"\(challenge.nonce)\""
            header += ", uri=\"\(digestURI)\""
            header += ", response=\"\(response)\""
            header += ", algorithm=\(challenge.algorithm)"
            if let opaque = challenge.opaque {
                header += ", opaque=\"\(opaque)\""
            }
            return header
        }
    }

    private static func md5Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
