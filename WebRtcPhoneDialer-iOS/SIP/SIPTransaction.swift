import Foundation

enum SIPTransactionState {
    case calling    // INVITE sent, waiting for response
    case trying     // Non-INVITE sent, waiting for response
    case proceeding // 1xx received
    case completed  // Final response received
    case confirmed  // ACK sent (INVITE only)
    case terminated
}

class SIPTransaction {
    let id: String
    let method: String
    let callID: String
    let branch: String
    var state: SIPTransactionState
    var request: SIPMessage
    var lastResponse: SIPMessage?
    var onResponse: ((SIPMessage) -> Void)?
    var onTimeout: (() -> Void)?
    private var timeoutTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.webrtcphonedialer.transaction")

    init(request: SIPMessage) {
        self.request = request
        self.method = request.method ?? "UNKNOWN"
        self.callID = request.callID ?? ""
        self.branch = request.via?.branch ?? ""
        self.id = "\(callID)-\(branch)"
        self.state = method == "INVITE" ? .calling : .trying
    }

    func startTimeout(seconds: TimeInterval = 32) {
        timeoutTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in
            self?.state = .terminated
            self?.onTimeout?()
        }
        timer.resume()
        timeoutTimer = timer
    }

    func cancelTimeout() {
        timeoutTimer?.cancel()
        timeoutTimer = nil
    }

    func processResponse(_ response: SIPMessage) {
        guard let code = response.statusCode else { return }
        lastResponse = response

        if code >= 100 && code < 200 {
            state = .proceeding
        } else if code >= 200 && code < 300 {
            state = method == "INVITE" ? .completed : .terminated
            cancelTimeout()
        } else if code >= 300 {
            state = .completed
            cancelTimeout()
        }

        onResponse?(response)
    }

    func confirm() {
        state = .confirmed
    }

    func terminate() {
        cancelTimeout()
        state = .terminated
    }

    /// Match a response to this transaction by branch and method
    func matches(response: SIPMessage) -> Bool {
        guard let via = response.via,
              let cseq = response.cseq else { return false }
        return via.branch == branch && cseq.method == method
    }
}

class SIPTransactionManager {
    private var transactions: [String: SIPTransaction] = [:]
    private let lock = NSLock()

    func add(_ transaction: SIPTransaction) {
        lock.lock()
        transactions[transaction.id] = transaction
        lock.unlock()
    }

    func remove(_ transactionID: String) {
        lock.lock()
        transactions.removeValue(forKey: transactionID)
        lock.unlock()
    }

    func findTransaction(for response: SIPMessage) -> SIPTransaction? {
        lock.lock()
        defer { lock.unlock() }
        return transactions.values.first(where: { $0.matches(response: response) })
    }

    func findByCallID(_ callID: String) -> SIPTransaction? {
        lock.lock()
        defer { lock.unlock() }
        return transactions.values.first(where: { $0.callID == callID })
    }

    func removeAll() {
        lock.lock()
        for tx in transactions.values {
            tx.terminate()
        }
        transactions.removeAll()
        lock.unlock()
    }
}
