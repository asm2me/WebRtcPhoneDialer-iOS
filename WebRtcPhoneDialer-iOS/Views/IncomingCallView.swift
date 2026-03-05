import SwiftUI

struct IncomingCallView: View {
    @StateObject private var viewModel = IncomingCallViewModel()
    let callerID: String
    let onAnswer: () -> Void
    let onReject: () -> Void

    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [Color(hex: "0D0D1A"), Color(hex: "1A1A3E")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Pulsing ring indicator
                ZStack {
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.5 : 1.0)
                        .opacity(pulseAnimation ? 0.0 : 0.5)

                    Circle()
                        .stroke(Color.green.opacity(0.5), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0.0 : 0.7)

                    Image(systemName: "phone.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                        .frame(width: 100, height: 100)
                        .background(Color.green.opacity(0.2))
                        .clipShape(Circle())
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        pulseAnimation = true
                    }
                }

                // Caller info
                VStack(spacing: 8) {
                    Text(callerID)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(Color(hex: "CCCCEE"))

                    Text("Incoming Call...")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "666688"))
                }

                Spacer()

                // Action buttons
                HStack(spacing: 60) {
                    // Reject
                    Button {
                        viewModel.stopRingtone()
                        onReject()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .frame(width: 72, height: 72)
                                .background(Color.red)
                                .clipShape(Circle())
                            Text("Reject")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "666688"))
                        }
                    }

                    // Mute ringtone
                    Button {
                        viewModel.muteRingtone()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color(hex: "CCCCEE"))
                                .frame(width: 56, height: 56)
                                .background(Color(hex: "1A1A2E"))
                                .clipShape(Circle())
                            Text("Mute")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "666688"))
                        }
                    }

                    // Answer
                    Button {
                        viewModel.stopRingtone()
                        onAnswer()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .frame(width: 72, height: 72)
                                .background(Color.green)
                                .clipShape(Circle())
                            Text("Answer")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "666688"))
                        }
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            viewModel.configure(callerID: callerID)
        }
        .onDisappear {
            viewModel.stopRingtone()
        }
    }
}
