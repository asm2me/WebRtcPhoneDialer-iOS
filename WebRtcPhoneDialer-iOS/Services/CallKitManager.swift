import Foundation
import CallKit
import AVFoundation

protocol CallKitManagerDelegate: AnyObject {
    func callKitDidAnswerCall()
    func callKitDidEndCall()
    func callKitDidSetHeld(_ held: Bool)
    func callKitDidSetMuted(_ muted: Bool)
    func callKitDidActivateAudioSession()
    func callKitDidDeactivateAudioSession()
}

class CallKitManager: NSObject {
    weak var delegate: CallKitManagerDelegate?

    private let provider: CXProvider
    private let callController = CXCallController()
    private var activeCallUUID: UUID?

    override init() {
        let config = CXProviderConfiguration()
        config.localizedName = "VOIPAT Phone"
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportsVideo = false
        config.supportedHandleTypes = [.phoneNumber, .generic]
        config.includesCallsInRecents = true

        self.provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: - Outgoing call

    func reportOutgoingCall(to handle: String, uuid: UUID = UUID()) {
        activeCallUUID = uuid

        let handleType: CXHandle.HandleType = handle.contains("@") ? .generic : .phoneNumber
        let cxHandle = CXHandle(type: handleType, value: handle)

        let startCallAction = CXStartCallAction(call: uuid, handle: cxHandle)
        startCallAction.isVideo = false

        let transaction = CXTransaction(action: startCallAction)
        callController.request(transaction) { error in
            if let error = error {
                Log.app.error("Failed to report outgoing call: \(error.localizedDescription)")
            }
        }
    }

    func reportOutgoingCallConnecting() {
        guard let uuid = activeCallUUID else { return }
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
    }

    func reportOutgoingCallConnected() {
        guard let uuid = activeCallUUID else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    // MARK: - Incoming call

    func reportIncomingCall(from handle: String, uuid: UUID = UUID(), completion: @escaping (Error?) -> Void) {
        activeCallUUID = uuid

        let update = CXCallUpdate()
        let handleType: CXHandle.HandleType = handle.contains("@") ? .generic : .phoneNumber
        update.remoteHandle = CXHandle(type: handleType, value: handle)
        update.localizedCallerName = handle
        update.hasVideo = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = true
        update.supportsDTMF = true

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error = error {
                Log.app.error("Failed to report incoming call: \(error.localizedDescription)")
            }
            completion(error)
        }
    }

    // MARK: - End call

    func endCall() {
        guard let uuid = activeCallUUID else { return }

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        callController.request(transaction) { error in
            if let error = error {
                Log.app.error("Failed to end call: \(error.localizedDescription)")
            }
        }
    }

    func reportCallEnded(reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = activeCallUUID else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        activeCallUUID = nil
    }

    // MARK: - Hold

    func setHeld(_ held: Bool) {
        guard let uuid = activeCallUUID else { return }
        let holdAction = CXSetHeldCallAction(call: uuid, onHold: held)
        let transaction = CXTransaction(action: holdAction)
        callController.request(transaction) { error in
            if let error = error {
                Log.app.error("Failed to set hold: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Mute

    func setMuted(_ muted: Bool) {
        guard let uuid = activeCallUUID else { return }
        let muteAction = CXSetMutedCallAction(call: uuid, muted: muted)
        let transaction = CXTransaction(action: muteAction)
        callController.request(transaction) { error in
            if let error = error {
                Log.app.error("Failed to set mute: \(error.localizedDescription)")
            }
        }
    }

    var hasActiveCall: Bool {
        activeCallUUID != nil
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        activeCallUUID = nil
        delegate?.callKitDidEndCall()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // Outgoing call started
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        delegate?.callKitDidAnswerCall()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        delegate?.callKitDidEndCall()
        activeCallUUID = nil
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        delegate?.callKitDidSetHeld(action.isOnHold)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        delegate?.callKitDidSetMuted(action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        delegate?.callKitDidActivateAudioSession()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        delegate?.callKitDidDeactivateAudioSession()
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        // DTMF is handled by our own UI, but CallKit may send this too
        action.fulfill()
    }
}
