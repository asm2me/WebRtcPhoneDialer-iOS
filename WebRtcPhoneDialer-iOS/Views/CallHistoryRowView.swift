import SwiftUI

struct CallHistoryRowView: View {
    @ObservedObject var call: CallSession

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            // Call direction icon
            Image(systemName: call.isIncoming ? "phone.arrow.down.left" : "phone.arrow.up.right")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "666688"))

            VStack(alignment: .leading, spacing: 2) {
                Text(PhoneNumberValidator.format(call.remoteParty))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: "CCCCEE"))

                HStack(spacing: 8) {
                    Text(call.stateDisplay)
                        .font(.system(size: 12))
                        .foregroundColor(statusColor)

                    if call.state == .ended || call.state == .connected {
                        Text(call.durationDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "666688"))
                    }
                }
            }

            Spacer()

            Text(call.dateDisplay)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "666688"))
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch call.state {
        case .ended, .connected: return .green
        case .failed: return .red
        default: return .gray
        }
    }
}
