import Foundation

class CallSession: Identifiable, ObservableObject {
    let id: UUID
    @Published var remoteParty: String
    @Published var startTime: Date
    @Published var endTime: Date?
    @Published var state: CallState
    @Published var errorMessage: String?
    @Published var isIncoming: Bool

    init(
        id: UUID = UUID(),
        remoteParty: String = "",
        startTime: Date = .now,
        endTime: Date? = nil,
        state: CallState = .idle,
        errorMessage: String? = nil,
        isIncoming: Bool = false
    ) {
        self.id = id
        self.remoteParty = remoteParty
        self.startTime = startTime
        self.endTime = endTime
        self.state = state
        self.errorMessage = errorMessage
        self.isIncoming = isIncoming
    }

    var duration: TimeInterval {
        guard let end = endTime else {
            if state == .connected || state == .onHold {
                return Date.now.timeIntervalSince(startTime)
            }
            return 0
        }
        return end.timeIntervalSince(startTime)
    }

    var durationDisplay: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var dateDisplay: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(startTime) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: startTime)
    }

    var stateDisplay: String {
        if state == .failed, let error = errorMessage {
            return "Failed: \(error)"
        }
        return state.displayString
    }
}
