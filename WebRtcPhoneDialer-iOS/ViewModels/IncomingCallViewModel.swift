import Foundation
import AVFoundation
import AudioToolbox
import SwiftUI

class IncomingCallViewModel: ObservableObject {
    @Published var callerID: String = "Unknown"
    @Published var statusText: String = "Incoming Call..."
    @Published var isMuted: Bool = false
    @Published var pulseScale: CGFloat = 1.0

    private var ringtonePlayer: AVAudioPlayer?
    private var ringtoneTimer: Timer?

    func configure(callerID: String) {
        self.callerID = callerID
        startRingtone()
    }

    func muteRingtone() {
        isMuted = true
        ringtonePlayer?.stop()
        ringtoneTimer?.invalidate()
    }

    func startRingtone() {
        guard !isMuted else { return }

        // Use system sound as default ringtone
        // On real device, you could bundle a .caf file
        playRingtoneOnce()

        // Loop ringtone every 3 seconds
        ringtoneTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.playRingtoneOnce()
        }
    }

    func stopRingtone() {
        ringtonePlayer?.stop()
        ringtoneTimer?.invalidate()
        ringtoneTimer = nil
    }

    private func playRingtoneOnce() {
        guard !isMuted else { return }

        // Try to use system ringtone or bundled ringtone
        if let url = Bundle.main.url(forResource: "ringtone", withExtension: "caf") {
            do {
                ringtonePlayer = try AVAudioPlayer(contentsOf: url)
                ringtonePlayer?.play()
            } catch {
                Log.audio.error("Failed to play ringtone: \(error.localizedDescription)")
            }
        } else {
            // Fallback: system alert sound
            AudioServicesPlayAlertSound(SystemSoundID(1005)) // SMS tone as fallback
        }
    }

    deinit {
        stopRingtone()
    }
}
