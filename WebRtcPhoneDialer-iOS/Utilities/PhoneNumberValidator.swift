import Foundation

struct PhoneNumberValidator {
    static func isValid(_ input: String?) -> Bool {
        guard let input = input?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
            return false
        }

        // SIP URI format: user@domain
        if input.contains("@") {
            let parts = input.components(separatedBy: "@")
            return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
        }

        // Phone number: strip non-digits, check 7-15 digits (E.164)
        let digits = input.filter { $0.isNumber }
        return digits.count >= 7 && digits.count <= 15
    }

    static func format(_ input: String?) -> String {
        guard let input = input?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
            return ""
        }

        // SIP URIs pass through unchanged
        if input.contains("@") {
            return input
        }

        let digits = input.filter { $0.isNumber }

        // US 10-digit: (XXX) XXX-XXXX
        if digits.count == 10 {
            let area = digits.prefix(3)
            let mid = digits.dropFirst(3).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(mid)-\(last)"
        }

        // US 11-digit starting with 1: +1 (XXX) XXX-XXXX
        if digits.count == 11 && digits.first == "1" {
            let area = digits.dropFirst(1).prefix(3)
            let mid = digits.dropFirst(4).prefix(3)
            let last = digits.suffix(4)
            return "+1 (\(area)) \(mid)-\(last)"
        }

        return input
    }
}
