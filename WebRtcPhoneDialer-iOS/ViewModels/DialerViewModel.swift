import Foundation
import Combine

class DialerViewModel: ObservableObject {
    @Published var phoneNumber: String = ""
    @Published var callDurationText: String = "0:00"
    @Published var showSettings: Bool = false
    @Published var showDebug: Bool = false
    @Published var showIncomingCall: Bool = false
    @Published var showDTMFPad: Bool = false

    private var durationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    let sipService: SIPService
    let callHistory: CallHistoryService

    init(sipService: SIPService, callHistory: CallHistoryService) {
        self.sipService = sipService
        self.callHistory = callHistory

        // Watch for incoming calls
        sipService.$currentCall
            .receive(on: DispatchQueue.main)
            .sink { [weak self] call in
                if let call = call, call.isIncoming && call.state == .ringing {
                    self?.showIncomingCall = true
                }
                if call == nil || call?.state == .ended || call?.state == .failed {
                    self?.showIncomingCall = false
                    self?.stopDurationTimer()
                }
                if call?.state == .connected {
                    self?.startDurationTimer()
                }
                // Add to history when call ends
                if let call = call, (call.state == .ended || call.state == .failed) {
                    self?.callHistory.addCall(call)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Dial Pad

    func appendDigit(_ digit: String) {
        if sipService.hasActiveCall {
            // Send DTMF
            if let char = digit.first {
                sipService.sendDTMF(char)
            }
        } else {
            phoneNumber += digit
        }
    }

    func deleteLastDigit() {
        guard !phoneNumber.isEmpty else { return }
        phoneNumber.removeLast()
    }

    func clearNumber() {
        phoneNumber = ""
    }

    // MARK: - Call Actions

    func callAction() {
        if sipService.hasActiveCall {
            sipService.endCall()
        } else {
            guard PhoneNumberValidator.isValid(phoneNumber) else { return }
            Task { await sipService.initiateCall(to: phoneNumber) }
        }
    }

    func holdAction() {
        guard let call = sipService.currentCall else { return }
        if call.state == .onHold {
            sipService.unholdCall()
        } else if call.state == .connected {
            sipService.holdCall()
        }
    }

    func hangupAction() {
        sipService.endCall()
    }

    func toggleMute() {
        if sipService.isMuted {
            sipService.unmuteMicrophone()
        } else {
            sipService.muteMicrophone()
        }
    }

    func toggleSpeaker() {
        sipService.toggleSpeaker()
    }

    // MARK: - Registration

    func toggleRegistration() {
        if sipService.isRegistered || sipService.registrationState == .registering {
            sipService.unregister()
        } else {
            Task { await sipService.register() }
        }
    }

    // MARK: - Incoming Call

    func answerIncomingCall() {
        showIncomingCall = false
        Task { await sipService.answerCall() }
    }

    func rejectIncomingCall() {
        showIncomingCall = false
        sipService.rejectCall()
    }

    // MARK: - History

    func dialFromHistory(_ call: CallSession) {
        phoneNumber = call.remoteParty
        callAction()
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let duration = self.sipService.getCallDuration()
            let total = Int(duration)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let seconds = total % 60
            if hours > 0 {
                self.callDurationText = String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                self.callDurationText = String(format: "%d:%02d", minutes, seconds)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        callDurationText = "0:00"
    }
}
