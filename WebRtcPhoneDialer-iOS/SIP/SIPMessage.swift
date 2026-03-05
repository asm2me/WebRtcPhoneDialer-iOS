import Foundation

enum SIPMessageType {
    case request
    case response
}

class SIPMessage {
    var type: SIPMessageType
    // Request fields
    var method: String?
    var requestURI: SIPURI?
    // Response fields
    var statusCode: Int?
    var reasonPhrase: String?
    // Common
    var headers: [(name: String, value: String)] = []
    var body: String = ""

    // Parsed header caches
    private var _via: SIPViaHeader?
    private var _from: SIPFromToHeader?
    private var _to: SIPFromToHeader?
    private var _cseq: SIPCSeqHeader?

    init(type: SIPMessageType) {
        self.type = type
    }

    // MARK: - Header access

    func headerValue(for name: String) -> String? {
        let lower = name.lowercased()
        return headers.first(where: { $0.name.lowercased() == lower })?.value
    }

    func headerValues(for name: String) -> [String] {
        let lower = name.lowercased()
        return headers.filter { $0.name.lowercased() == lower }.map { $0.value }
    }

    func setHeader(_ name: String, value: String) {
        let lower = name.lowercased()
        if let idx = headers.firstIndex(where: { $0.name.lowercased() == lower }) {
            headers[idx] = (name: name, value: value)
        } else {
            headers.append((name: name, value: value))
        }
    }

    func addHeader(_ name: String, value: String) {
        headers.append((name: name, value: value))
    }

    var callID: String? {
        get { headerValue(for: "Call-ID") }
        set { if let v = newValue { setHeader("Call-ID", value: v) } }
    }

    var via: SIPViaHeader? {
        get {
            if _via == nil, let v = headerValue(for: "Via") {
                _via = SIPViaHeader(parsing: v)
            }
            return _via
        }
        set {
            _via = newValue
            if let v = newValue {
                setHeader("Via", value: v.headerValue)
            }
        }
    }

    var from: SIPFromToHeader? {
        get {
            if _from == nil, let v = headerValue(for: "From") {
                _from = SIPFromToHeader(parsing: v)
            }
            return _from
        }
        set {
            _from = newValue
            if let v = newValue {
                setHeader("From", value: v.headerValue)
            }
        }
    }

    var to: SIPFromToHeader? {
        get {
            if _to == nil, let v = headerValue(for: "To") {
                _to = SIPFromToHeader(parsing: v)
            }
            return _to
        }
        set {
            _to = newValue
            if let v = newValue {
                setHeader("To", value: v.headerValue)
            }
        }
    }

    var cseq: SIPCSeqHeader? {
        get {
            if _cseq == nil, let v = headerValue(for: "CSeq") {
                _cseq = SIPCSeqHeader(parsing: v)
            }
            return _cseq
        }
        set {
            _cseq = newValue
            if let v = newValue {
                setHeader("CSeq", value: v.headerValue)
            }
        }
    }

    var contentType: String? {
        get { headerValue(for: "Content-Type") }
        set { if let v = newValue { setHeader("Content-Type", value: v) } }
    }

    var contentLength: Int {
        get { Int(headerValue(for: "Content-Length") ?? "0") ?? 0 }
        set { setHeader("Content-Length", value: "\(newValue)") }
    }

    // MARK: - Serialization

    func serialize() -> String {
        var lines: [String] = []

        // Start line
        switch type {
        case .request:
            guard let method = method, let uri = requestURI else { return "" }
            lines.append("\(method) \(uri) SIP/2.0")
        case .response:
            guard let code = statusCode else { return "" }
            let reason = reasonPhrase ?? SIPMessage.reasonPhrase(for: code)
            lines.append("SIP/2.0 \(code) \(reason)")
        }

        // Update Content-Length
        let bodyData = body.data(using: .utf8) ?? Data()
        setHeader("Content-Length", value: "\(bodyData.count)")

        // Headers
        for header in headers {
            lines.append("\(header.name): \(header.value)")
        }

        // Empty line + body
        lines.append("")
        if !body.isEmpty {
            lines.append(body)
        }

        return lines.joined(separator: "\r\n")
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> SIPMessage? {
        let crlf = text.contains("\r\n") ? "\r\n" : "\n"
        let parts = text.components(separatedBy: "\(crlf)\(crlf)")
        let headerSection = parts[0]
        let bodySection = parts.count > 1 ? parts.dropFirst().joined(separator: "\(crlf)\(crlf)") : ""

        let lines = headerSection.components(separatedBy: crlf)
        guard !lines.isEmpty else { return nil }

        let firstLine = lines[0]
        let message: SIPMessage

        if firstLine.hasPrefix("SIP/2.0") {
            // Response
            message = SIPMessage(type: .response)
            let responseParts = firstLine.components(separatedBy: " ")
            guard responseParts.count >= 2,
                  let code = Int(responseParts[1]) else { return nil }
            message.statusCode = code
            message.reasonPhrase = responseParts.count > 2
                ? responseParts[2...].joined(separator: " ")
                : reasonPhrase(for: code)
        } else {
            // Request
            message = SIPMessage(type: .request)
            let requestParts = firstLine.components(separatedBy: " ")
            guard requestParts.count >= 3 else { return nil }
            message.method = requestParts[0]
            message.requestURI = SIPURI.parse(requestParts[1])
        }

        // Parse headers (handling line continuations)
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { continue }

            if let colonIdx = line.firstIndex(of: ":") {
                let name = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

                // Expand compact header names
                let expandedName = SIPMessage.expandCompactHeader(name)
                message.headers.append((name: expandedName, value: value))
            }
        }

        message.body = bodySection
        return message
    }

    // MARK: - Request builders

    static func createRequest(
        method: String,
        requestURI: SIPURI,
        from: SIPFromToHeader,
        to: SIPFromToHeader,
        callID: String,
        cseq: Int,
        via: SIPViaHeader,
        contact: SIPContactHeader? = nil,
        body: String = "",
        contentType: String? = nil
    ) -> SIPMessage {
        let msg = SIPMessage(type: .request)
        msg.method = method
        msg.requestURI = requestURI
        msg.via = via
        msg.from = from
        msg.to = to
        msg.callID = callID
        msg.cseq = SIPCSeqHeader(sequenceNumber: cseq, method: method)
        msg.setHeader("Max-Forwards", value: "70")

        if let contact = contact {
            msg.setHeader("Contact", value: contact.headerValue)
        }

        if !body.isEmpty, let ct = contentType {
            msg.contentType = ct
            msg.body = body
        }

        msg.setHeader("User-Agent", value: "VOIPAT-Phone-iOS/1.0")

        return msg
    }

    static func createResponse(
        statusCode: Int,
        forRequest request: SIPMessage,
        contact: SIPContactHeader? = nil,
        body: String = "",
        contentType: String? = nil
    ) -> SIPMessage {
        let msg = SIPMessage(type: .response)
        msg.statusCode = statusCode
        msg.reasonPhrase = reasonPhrase(for: statusCode)

        // Copy Via, From, To, Call-ID, CSeq from request
        for header in request.headers {
            let lower = header.name.lowercased()
            if lower == "via" || lower == "from" || lower == "call-id" || lower == "cseq" {
                msg.addHeader(header.name, value: header.value)
            }
        }

        // Copy To from request, adding tag if not present
        if let toHeader = request.to {
            var toWithTag = toHeader
            if toWithTag.tag == nil {
                toWithTag.tag = SIPFromToHeader.generateTag()
            }
            msg.setHeader("To", value: toWithTag.headerValue)
        }

        if let contact = contact {
            msg.setHeader("Contact", value: contact.headerValue)
        }

        if !body.isEmpty, let ct = contentType {
            msg.contentType = ct
            msg.body = body
        }

        msg.setHeader("User-Agent", value: "VOIPAT-Phone-iOS/1.0")

        return msg
    }

    // MARK: - Helpers

    static func reasonPhrase(for code: Int) -> String {
        switch code {
        case 100: return "Trying"
        case 180: return "Ringing"
        case 183: return "Session Progress"
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 407: return "Proxy Authentication Required"
        case 408: return "Request Timeout"
        case 486: return "Busy Here"
        case 487: return "Request Terminated"
        case 488: return "Not Acceptable Here"
        case 500: return "Server Internal Error"
        case 503: return "Service Unavailable"
        case 603: return "Decline"
        default: return "Unknown"
        }
    }

    static func expandCompactHeader(_ name: String) -> String {
        switch name {
        case "v": return "Via"
        case "f": return "From"
        case "t": return "To"
        case "i": return "Call-ID"
        case "m": return "Contact"
        case "l": return "Content-Length"
        case "c": return "Content-Type"
        default: return name
        }
    }

    static func generateCallID(domain: String) -> String {
        return "\(UUID().uuidString.lowercased())@\(domain)"
    }

    static func generateBranch() -> String {
        return "z9hG4bK-\(UUID().uuidString.prefix(16))"
    }
}
