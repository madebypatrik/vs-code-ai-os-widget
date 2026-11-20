import AgentPillCore
import SwiftUI

enum Theme {
    static let cardBackground = Color(hex: 0x141414)
    static let buttonBackground = Color(hex: 0x2C2C2A)
    /// Brand color: tells the VS Code and Claude pills apart (VS Code blue).
    static let brand = Color(hex: 0x007ACC)
    static let brandSymbol = "chevron.left.forwardslash.chevron.right"
    static let source = brand
    static let orange = Color(hex: 0xEF9F27)
    static let green = Color(hex: 0x1D9E75)
    static let gray = Color(hex: 0x8E8E8A)
    static let secondaryText = Color(hex: 0xB4B2A9)
    static let bodyText = Color(hex: 0xD3D1C7)
    static let cardWidth: CGFloat = 340
    static let cardRadius: CGFloat = 18

    static func color(for state: AgentState) -> Color {
        switch state.displayState {
        case .needsApproval: orange
        case .yourTurn: green
        default: gray
        }
    }

    static func pillLabel(for state: AgentState) -> String {
        switch state.displayState {
        case .needsApproval: "Väntar"
        case .yourTurn: "Din tur"
        case .working, .toolPending: "Arbetar"
        case .idle: ""
        }
    }

    /// "0:42", "12:05", "1:02:33"
    static func elapsed(since date: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(date)))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
