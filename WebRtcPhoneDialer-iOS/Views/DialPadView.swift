import SwiftUI

struct DialPadView: View {
    let onDigitTapped: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(80), spacing: 16), count: 3)
    private let digits: [(String, String)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", "")
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(digits, id: \.0) { digit, subtitle in
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onDigitTapped(digit)
                } label: {
                    VStack(spacing: 2) {
                        Text(digit)
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "CCCCEE"))
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(hex: "666688"))
                        }
                    }
                    .frame(width: 72, height: 72)
                    .background(Color(hex: "1A1A2E"))
                    .clipShape(Circle())
                }
            }
        }
    }
}

// MARK: - Color extension for hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
