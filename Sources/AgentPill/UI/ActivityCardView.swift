import AgentPillCore
import Observation
import SwiftUI

@MainActor
@Observable
final class PanelModel {
    var isVisible = false
    /// false = small always-on widget, true = full Live Activity card.
    var isExpanded = false
    /// Close button (×) on the card.
    @ObservationIgnored var onClose: (() -> Void)?
}

/// The full Live Activity–style card (expanded widget).
struct ActivityCardView: View {
    let store: SessionStore
    let panel: PanelModel
    let port: UInt16
    let onOpen: (Session?) -> Void
    let onSnooze: () -> Void

    private var sessions: [Session] { store.sessions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 8)
            content.padding(.bottom, 14)
            buttons
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 16, trailing: 18))
        .frame(width: Theme.cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.brand.opacity(0.55), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text("VS Code · Copilot")
                .foregroundStyle(Theme.source)
            Spacer()
            Text(headerTrailing)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Button { panel.onClose?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.buttonBackground))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stäng (visas igen om 2 min om du fortfarande behövs)")
        }
        .font(.system(size: 13))
    }

    private var headerTrailing: String {
        switch sessions.count {
        case 0: ""
        case 1: sessions[0].projectName
        default: "\(sessions.count) sessioner"
        }
    }

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ingen aktiv session")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                Text("Lyssnar på 127.0.0.1:\(String(port))")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.bodyText)
            }
        } else if sessions.count == 1 {
            VStack(alignment: .leading, spacing: 4) {
                title(for: sessions[0])
                subtitle(for: sessions[0])
            }
        } else {
            VStack(spacing: 2) {
                ForEach(sessions) { session in
                    SessionRow(session: session, now: store.now) { onOpen(session) }
                }
            }
        }
    }

    private func title(for session: Session) -> some View {
        // Mockup: "Väntar på <godkännande>" with the key word in the accent color.
        let (lead, accentWord): (String, String) = switch session.state.displayState {
        case .needsApproval: ("Väntar på ", "godkännande")
        case .yourTurn: ("Svaret är klart – ", "din tur")
        default: ("Arbetar", "")
        }
        let accent = session.state.needsAttention ? Theme.color(for: session.state) : .white
        return Text("\(Text(lead).foregroundStyle(.white))\(Text(accentWord).foregroundStyle(accent))")
            .font(.system(size: 20, weight: .medium))
    }

    private func subtitle(for session: Session) -> some View {
        let time = Theme.elapsed(since: session.stateSince, now: store.now)
        let detail: Text
        if session.state == .needsApproval || session.state == .toolPending, let tool = session.pendingTool {
            detail = toolText(tool)
        } else if session.state == .yourTurn {
            detail = Text("Väntat")
        } else {
            detail = Text("Pågår")
        }
        return Text("\(detail) · \(Text(time).monospacedDigit())")
            .font(.system(size: 14))
            .foregroundStyle(Theme.bodyText)
            .lineLimit(2)
    }

    private func toolText(_ tool: ToolSummary) -> Text {
        if tool.isCommand, let command = tool.detail {
            return Text("Vill köra \(Text(command).font(.system(size: 13, design: .monospaced)))")
        }
        return Text(tool.displayText)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button("Öppna VS Code") { onOpen(store.attentionSessions.first ?? sessions.first) }
                .buttonStyle(CardButtonStyle())
            Button("Påminn om 5 min", action: onSnooze)
                .buttonStyle(CardButtonStyle(foreground: Theme.secondaryText))
                .disabled(store.attentionSessions.isEmpty)
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let now: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                StatusDot(state: session.state, size: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Theme.elapsed(since: session.stateSince, now: now))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(session.state.needsAttention ? Theme.color(for: session.state) : Theme.gray)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.06 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var statusLine: String {
        switch session.state.displayState {
        case .needsApproval: session.pendingTool?.plainText ?? "Väntar på godkännande"
        case .yourTurn: "Din tur"
        default: "Arbetar"
        }
    }
}

private struct CardButtonStyle: ButtonStyle {
    var foreground: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.buttonBackground.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
