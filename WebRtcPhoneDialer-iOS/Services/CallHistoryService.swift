import Foundation

class CallHistoryService: ObservableObject {
    @Published var calls: [CallSession] = []

    func addCall(_ call: CallSession) {
        DispatchQueue.main.async {
            self.calls.insert(call, at: 0)
        }
    }

    func removeCall(at index: Int) {
        guard index >= 0 && index < calls.count else { return }
        calls.remove(at: index)
    }

    func removeCall(_ call: CallSession) {
        calls.removeAll(where: { $0.id == call.id })
    }

    func clearHistory() {
        calls.removeAll()
    }

    var totalCallCount: Int {
        calls.count
    }

    var totalCallDuration: TimeInterval {
        calls.reduce(0) { $0 + $1.duration }
    }
}
