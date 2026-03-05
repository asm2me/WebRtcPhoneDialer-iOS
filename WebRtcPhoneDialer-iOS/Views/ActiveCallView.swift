import SwiftUI

struct ActiveCallView: View {
    @EnvironmentObject var sipService: SIPService
    @ObservedObject var viewModel: DialerViewModel
    @State private var showDTMFPad = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Call info
            VStack(spacing: 8) {
                Text(sipService.currentCall?.remoteParty ?? "")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Color(hex: "CCCCEE"))

                Text(sipService.currentCall?.state.displayString ?? "")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "666688"))

                if sipService.currentCall?.state == .connected || sipService.currentCall?.state == .onHold {
                    Text(viewModel.callDurationText)
                        .font(.system(size: 20, weight: .light, design: .monospaced))
                        .foregroundColor(Color(hex: "CCCCEE"))
                }
            }

            Spacer()

            // DTMF Pad (toggleable)
            if showDTMFPad {
                DialPadView { digit in
                    viewModel.appendDigit(digit)
                }
                .padding(.horizontal, 20)
            }

            // Control buttons
            HStack(spacing: 32) {
                // Mute
                CallControlButton(
                    icon: sipService.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: "Mute",
                    isActive: sipService.isMuted,
                    activeColor: .red
                ) {
                    viewModel.toggleMute()
                }

                // Keypad
                CallControlButton(
                    icon: "circle.grid.3x3.fill",
                    label: "Keypad",
                    isActive: showDTMFPad,
                    activeColor: .blue
                ) {
                    showDTMFPad.toggle()
                }

                // Speaker
                CallControlButton(
                    icon: sipService.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                    label: "Speaker",
                    isActive: sipService.isSpeakerOn,
                    activeColor: .blue
                ) {
                    viewModel.toggleSpeaker()
                }

                // Hold
                CallControlButton(
                    icon: sipService.currentCall?.state == .onHold ? "play.fill" : "pause.fill",
                    label: sipService.currentCall?.state == .onHold ? "Resume" : "Hold",
                    isActive: sipService.currentCall?.state == .onHold,
                    activeColor: .orange
                ) {
                    viewModel.holdAction()
                }
            }

            // Hangup button
            Button {
                viewModel.hangupAction()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "0D0D1A"))
    }
}

struct CallControlButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    var activeColor: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(isActive ? activeColor : Color(hex: "CCCCEE"))
                    .frame(width: 56, height: 56)
                    .background(isActive ? activeColor.opacity(0.2) : Color(hex: "1A1A2E"))
                    .clipShape(Circle())

                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "666688"))
            }
        }
    }
}
