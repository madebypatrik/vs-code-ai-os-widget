import AgentPillCore
import SwiftUI

/// Panel root: small always-on widget, or the full card when expanded.
struct WidgetContainer: View {
    let store: SessionStore
    let panel: PanelModel
    let port: UInt16
    let onOpen: (Session?) -> Void
    let onSnooze: () -> Void

    var body: some View {
        Group {
            if panel.isExpanded {
                ActivityCardView(store: store, panel: panel, port: port, onOpen: onOpen, onSnooze: onSnooze)
            } else {
                CompactWidgetView(store: store, onOpen: onOpen, onSnooze: onSnooze, onExpand: { panel.isExpanded = true })
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .padding(EdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16)) // room for the shadow
        .scaleEffect(panel.isVisible ? 1 : 0.6, anchor: .top)
        .opacity(panel.isVisible ? 1 : 0)
        .animation(.spring(duration: 0.2), value: panel.isVisible)
        .animation(.spring(duration: 0.2), value: panel.isExpanded)
        .environment(\.colorScheme, .dark)
    }
}

/// Small widget: one compact row per session. Click a row to open VS Code.
struct CompactWidgetView: View {
    static let width: CGFloat = 240

    let store: SessionStore
    let onOpen: (Session?) -> Void
    let onSnooze: () -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            if store.sessions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.gray)
                    Text("Ingen aktiv session")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            } else {
                ForEach(store.sessions) { session in
                    CompactRow(session: session, now: store.now) { onOpen(session) }
                        .contextMenu {
                            Button("Öppna VS Code") { onOpen(session) }
                            Button("Påminn om 5 min", action: onSnooze)
                                .disabled(!session.state.needsAttention)
                            Button("Visa detaljer", action: onExpand)
                        }
                }
            }
        }
        .padding(6)
        .frame(width: Self.width)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.brand.opacity(0.55), lineWidth: 1)
        )
    }
}

private struct CompactRow: View {
    let session: Session
    let now: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                StatusDot(state: session.state, size: 7)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(session.state.needsAttention ? Theme.color(for: session.state) : .white)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                Text(Theme.elapsed(since: session.stateSince, now: now))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.gray)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hovering ? 0.07 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Öppna \(session.projectName) i VS Code")
    }

    private var title: String {
        switch session.state.displayState {
        case .needsApproval: "Väntar på godkännande"
        case .yourTurn: "Din tur"
        default: "Arbetar"
        }
    }

    private var detail: String {
        if session.state == .needsApproval, let tool = session.pendingTool {
            return "\(session.projectName) · \(tool.isCommand ? tool.detail ?? tool.name : tool.name)"
        }
        return session.projectName
    }
}
