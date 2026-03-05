import Foundation

protocol WSSChannelDelegate: AnyObject {
    func wssChannel(_ channel: WSSChannel, didReceiveMessage message: String)
    func wssChannel(_ channel: WSSChannel, didDisconnectWithError error: Error?)
    func wssChannelDidConnect(_ channel: WSSChannel)
}

class WSSChannel: NSObject {
    weak var delegate: WSSChannelDelegate?

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private let queue = DispatchQueue(label: "com.webrtcphonedialer.wss", qos: .userInteractive)

    var connected: Bool { isConnected }

    func connect(to urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw WSSError.invalidURL
        }

        // Create session that trusts self-signed certificates
        let sessionDelegate = WSSSessionDelegate()
        urlSession = URLSession(configuration: .default, delegate: sessionDelegate, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.setValue("sip", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.timeoutInterval = 30

        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()

        isConnected = true
        delegate?.wssChannelDidConnect(self)
        startReceiving()

        Log.sip.info("WSS connected to \(urlString)")
    }

    func send(_ message: String) async throws {
        guard let webSocket = webSocket, isConnected else {
            throw WSSError.notConnected
        }
        try await webSocket.send(.string(message))
        Log.sip.debug(">> Sent SIP message (\(message.count) bytes)")
    }

    func disconnect() {
        isConnected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        Log.sip.info("WSS disconnected")
    }

    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            guard let self = self, self.isConnected else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    Log.sip.debug("<< Received SIP message (\(text.count) bytes)")
                    self.delegate?.wssChannel(self, didReceiveMessage: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.delegate?.wssChannel(self, didReceiveMessage: text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self.startReceiving()

            case .failure(let error):
                Log.sip.error("WSS receive error: \(error.localizedDescription)")
                self.isConnected = false
                self.delegate?.wssChannel(self, didDisconnectWithError: error)
            }
        }
    }
}

// MARK: - TLS delegate for self-signed certificates

private class WSSSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Trust self-signed certificates (matching C# behavior: ServicePointManager.ServerCertificateValidationCallback)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

enum WSSError: Error, LocalizedError {
    case invalidURL
    case notConnected
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WebSocket URL"
        case .notConnected: return "WebSocket is not connected"
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        }
    }
}
