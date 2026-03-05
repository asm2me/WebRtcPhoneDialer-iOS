import Foundation

enum RegistrationState: String, Codable, Sendable {
    case unregistered
    case registering
    case registered
    case failed

    var displayString: String {
        switch self {
        case .unregistered: return "Not Registered"
        case .registering: return "Registering..."
        case .registered: return "Registered"
        case .failed: return "Registration Failed"
        }
    }
}
