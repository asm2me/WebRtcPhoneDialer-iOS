import SwiftUI

struct CallHistoryView: View {
    @EnvironmentObject var callHistory: CallHistoryService
    let onDial: (CallSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Call History")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "666688"))

                Spacer()

                if !callHistory.calls.isEmpty {
                    Button("Clear All") {
                        callHistory.clearHistory()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "666688"))
                }
            }
            .padding(.horizontal, 16)

            if callHistory.calls.isEmpty {
                Text("No call history")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "444466"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                List {
                    ForEach(callHistory.calls) { call in
                        CallHistoryRowView(call: call)
                            .listRowBackground(Color(hex: "0D0D1A"))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onDial(call)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    callHistory.removeCall(call)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    onDial(call)
                                } label: {
                                    Label("Dial", systemImage: "phone")
                                }
                                Button {
                                    UIPasteboard.general.string = call.remoteParty
                                } label: {
                                    Label("Copy Number", systemImage: "doc.on.doc")
                                }
                                Button(role: .destructive) {
                                    callHistory.removeCall(call)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}
