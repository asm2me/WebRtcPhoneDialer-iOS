import SwiftUI

struct DialerView: View {
    @EnvironmentObject var sipService: SIPService
    @EnvironmentObject var callHistory: CallHistoryService
    @StateObject private var viewModel: ViewModelWrapper = ViewModelWrapper()

    var body: some View {
        ZStack {
            // Background
            Color(hex: "0D0D1A").ignoresSafeArea()

            if let vm = viewModel.dialerVM {
                mainContent(vm: vm)
                    .fullScreenCover(isPresented: Binding(
                        get: { vm.showIncomingCall },
                        set: { vm.showIncomingCall = $0 }
                    )) {
                        IncomingCallView(
                            callerID: sipService.currentCall?.remoteParty ?? "Unknown",
                            onAnswer: { vm.answerIncomingCall() },
                            onReject: { vm.rejectIncomingCall() }
                        )
                    }
            }
        }
        .onAppear {
            if viewModel.dialerVM == nil {
                viewModel.dialerVM = DialerViewModel(sipService: sipService, callHistory: callHistory)
            }
        }
    }

    @ViewBuilder
    private func mainContent(vm: DialerViewModel) -> some View {
        if sipService.hasActiveCall {
            ActiveCallView(viewModel: vm)
                .environmentObject(sipService)
        } else {
            dialerContent(vm: vm)
        }
    }

    private func dialerContent(vm: DialerViewModel) -> some View {
        VStack(spacing: 0) {
            // Top bar: Registration status + buttons
            topBar(vm: vm)

            // Call status
            if sipService.currentCall != nil {
                callStatusBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Phone number input
            phoneNumberInput(vm: vm)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            // Dial pad
            DialPadView { digit in
                vm.appendDigit(digit)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Action buttons
            actionButtons(vm: vm)
                .padding(.top, 16)

            // Call history
            CallHistoryView { call in
                vm.dialFromHistory(call)
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 8)
        }
        .sheet(isPresented: Binding(
            get: { vm.showSettings },
            set: { vm.showSettings = $0 }
        )) {
            SettingsView(sipService: sipService)
        }
        .sheet(isPresented: Binding(
            get: { vm.showDebug },
            set: { vm.showDebug = $0 }
        )) {
            DebugView(sipService: sipService)
                .environmentObject(sipService)
        }
    }

    // MARK: - Top Bar

    private func topBar(vm: DialerViewModel) -> some View {
        HStack(spacing: 12) {
            // Registration status
            HStack(spacing: 6) {
                Circle()
                    .fill(registrationColor)
                    .frame(width: 8, height: 8)
                Text(sipService.registrationMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "888899"))
                    .lineLimit(1)
            }

            Spacer()

            // Register button
            Button {
                vm.toggleRegistration()
            } label: {
                Text(sipService.isRegistered ? "Unregister" : "Register")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "CCCCEE"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "1A1A2E"))
                    .cornerRadius(6)
            }
            .disabled(sipService.registrationState == .registering)

            // Debug button
            Button {
                vm.showDebug = true
            } label: {
                Image(systemName: "ant")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "888899"))
            }

            // Settings button
            Button {
                vm.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "888899"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "111122"))
    }

    // MARK: - Call Status

    private var callStatusBar: some View {
        HStack {
            Text(sipService.currentCall?.state.displayString ?? "")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "CCCCEE"))
            Spacer()
        }
    }

    // MARK: - Phone Number Input

    private func phoneNumberInput(vm: DialerViewModel) -> some View {
        HStack {
            TextField("Enter number or SIP address", text: Binding(
                get: { vm.phoneNumber },
                set: { vm.phoneNumber = $0 }
            ))
            .font(.system(size: 22, weight: .light, design: .monospaced))
            .foregroundColor(Color(hex: "CCCCEE"))
            .keyboardType(.phonePad)
            .multilineTextAlignment(.center)
            .tint(Color(hex: "4466FF"))

            if !vm.phoneNumber.isEmpty {
                Button {
                    vm.deleteLastDigit()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "666688"))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "111122"))
        .cornerRadius(10)
    }

    // MARK: - Action Buttons

    private func actionButtons(vm: DialerViewModel) -> some View {
        HStack(spacing: 24) {
            Spacer()

            // Clear button
            Button {
                vm.clearNumber()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: "666688"))
                    .frame(width: 56, height: 56)
            }

            // Call button
            Button {
                vm.callAction()
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(
                        PhoneNumberValidator.isValid(vm.phoneNumber) && sipService.isRegistered
                            ? Color.green : Color.green.opacity(0.3)
                    )
                    .clipShape(Circle())
            }
            .disabled(!PhoneNumberValidator.isValid(vm.phoneNumber) || !sipService.isRegistered)

            // Placeholder for symmetry
            Color.clear
                .frame(width: 56, height: 56)

            Spacer()
        }
    }

    // MARK: - Helpers

    private var registrationColor: Color {
        switch sipService.registrationState {
        case .unregistered: return .gray
        case .registering: return .orange
        case .registered: return .green
        case .failed: return .red
        }
    }
}

/// Wrapper to defer DialerViewModel creation until environment objects are available
private class ViewModelWrapper: ObservableObject {
    @Published var dialerVM: DialerViewModel?
}
