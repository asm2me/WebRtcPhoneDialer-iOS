import SwiftUI

struct DebugView: View {
    @EnvironmentObject var sipService: SIPService
    @StateObject private var viewModel: DebugViewModel
    @State private var selectedTab = 0

    init(sipService: SIPService) {
        _viewModel = StateObject(wrappedValue: DebugViewModel(sipService: sipService))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Registration info
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(registrationColor)
                            .frame(width: 8, height: 8)
                        Text(sipService.registrationState.displayString)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "CCCCEE"))
                    }

                    Text(viewModel.registrationInfo)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "888899"))
                        .lineLimit(nil)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "111122"))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Audio level meters
                VStack(spacing: 8) {
                    AudioLevelBar(label: "Mic", level: sipService.micLevel, color: .green)
                    AudioLevelBar(label: "Spk", level: sipService.speakerLevel, color: .blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Tab selector
                Picker("Log Type", selection: $selectedTab) {
                    Text("SIP Log").tag(0)
                    Text("RTP Log").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)

                // Log content
                if selectedTab == 0 {
                    sipLogView
                } else {
                    rtpLogView
                }
            }
            .background(Color(hex: "0D0D1A"))
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        if selectedTab == 0 {
                            viewModel.clearSIPLog()
                        } else {
                            viewModel.clearRTPLog()
                        }
                    }
                    .font(.system(size: 14))
                }
            }
        }
    }

    private var sipLogView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sipService.sipLog) { entry in
                        sipLogEntry(entry)
                            .id(entry.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: sipService.sipLog.count) { _ in
                if let lastEntry = sipService.sipLog.last {
                    proxy.scrollTo(lastEntry.id, anchor: .bottom)
                }
            }
        }
    }

    private func sipLogEntry(_ entry: SIPLogEntry) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(entry.timestampString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(hex: "555566"))

            Text(entry.directionSymbol)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(directionColor(entry.direction))

            Text(entry.message.prefix(500))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(messageColor(entry))
                .lineLimit(nil)
        }
    }

    private var rtpLogView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(sipService.rtpLog.enumerated()), id: \.offset) { index, entry in
                        Text(entry)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.cyan)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .onChange(of: sipService.rtpLog.count) { _ in
                proxy.scrollTo(sipService.rtpLog.count - 1, anchor: .bottom)
            }
        }
    }

    private func directionColor(_ direction: SIPLogDirection) -> Color {
        switch direction {
        case .outgoing: return .blue
        case .incoming: return .green
        case .info: return .yellow
        }
    }

    private func messageColor(_ entry: SIPLogEntry) -> Color {
        let msg = entry.message
        if msg.contains("4") && msg.hasPrefix("SIP/2.0 4") { return .red }
        if msg.contains("5") && msg.hasPrefix("SIP/2.0 5") { return .red }
        if msg.contains("6") && msg.hasPrefix("SIP/2.0 6") { return .red }
        switch entry.direction {
        case .outgoing: return Color(hex: "6699FF")
        case .incoming: return Color(hex: "66FF99")
        case .info: return Color(hex: "FFCC66")
        }
    }

    private var registrationColor: Color {
        switch sipService.registrationState {
        case .unregistered: return .gray
        case .registering: return .orange
        case .registered: return .green
        case .failed: return .red
        }
    }
}

struct AudioLevelBar: View {
    let label: String
    let level: Float
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "666688"))
                .frame(width: 30, alignment: .trailing)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "1A1A2E"))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(0, geometry.size.width * CGFloat(level)), height: 8)
                }
            }
            .frame(height: 8)

            Text("\(Int(level * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(hex: "666688"))
                .frame(width: 35, alignment: .trailing)
        }
    }
}
