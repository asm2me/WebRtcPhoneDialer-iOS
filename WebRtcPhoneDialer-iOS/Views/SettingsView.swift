import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SettingsViewModel

    init(sipService: SIPService) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(sipService: sipService))
    }

    var body: some View {
        NavigationStack {
            Form {
                // Service section
                Section("SIP Account") {
                    TextField("Username", text: $viewModel.username)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)

                    TextField("SIP Domain", text: $viewModel.sipDomain)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    TextField("Signaling Server URL (wss://...)", text: $viewModel.signalingServerUrl)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    SecureField("Auth Token", text: $viewModel.authToken)
                }

                Section("NAT Traversal") {
                    TextField("STUN Server", text: $viewModel.stunServer)
                        .autocapitalization(.none)

                    TextField("TURN Server", text: $viewModel.turnServer)
                        .autocapitalization(.none)

                    if !viewModel.turnServer.isEmpty {
                        TextField("TURN Username", text: $viewModel.turnUsername)
                            .autocapitalization(.none)

                        SecureField("TURN Password", text: $viewModel.turnPassword)
                    }

                    TextField("ICE Servers (one per line)", text: $viewModel.iceServers, axis: .vertical)
                        .autocapitalization(.none)
                        .lineLimit(3...6)
                }

                Section("Audio") {
                    Toggle("Enable Audio", isOn: $viewModel.enableAudio)

                    VStack(alignment: .leading) {
                        Text("Input Volume: \(Int(viewModel.inputVolume))%")
                            .font(.system(size: 14))
                        Slider(value: $viewModel.inputVolume, in: 0...100, step: 1)
                    }

                    VStack(alignment: .leading) {
                        Text("Output Volume: \(Int(viewModel.outputVolume))%")
                            .font(.system(size: 14))
                        Slider(value: $viewModel.outputVolume, in: 0...100, step: 1)
                    }

                    Toggle("Echo Cancellation", isOn: $viewModel.echoCancellation)
                    Toggle("Noise Suppression", isOn: $viewModel.noiseSuppression)

                    VStack(alignment: .leading) {
                        Text("Ring Volume: \(Int(viewModel.ringVolume))%")
                            .font(.system(size: 14))
                        Slider(value: $viewModel.ringVolume, in: 0...100, step: 1)
                    }
                }

                Section("Codecs") {
                    Picker("Audio Codec", selection: $viewModel.audioCodecName) {
                        ForEach(SettingsViewModel.audioCodecOptions, id: \.self) { codec in
                            Text(codec).tag(codec)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("App")
                        Spacer()
                        Text("VOIPAT Phone")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
