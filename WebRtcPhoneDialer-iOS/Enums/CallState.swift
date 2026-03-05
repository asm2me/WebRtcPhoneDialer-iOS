import Foundation

enum CallState: String, Codable, Sendable {
    case idle
    case initiating
    case ringing
    case connected
    case onHold
    case ended
    case failed

    var displayString: String {
        switch self {
        case .idle: return "Idle"
        case .initiating: return "Initiating..."
        case .ringing: return "Ringing..."
        case .connected: return "Connected"
        case .onHold: return "On Hold"
        case .ended: return "Ended"
        case .failed: return "Failed"
        }
    }
}
