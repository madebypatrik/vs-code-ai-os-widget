import AgentPillCore
import SwiftUI

/// The menu bar pill. Idle: just an icon. Otherwise a dark capsule with dot, status, project and waiting time.
struct PillView: View {
    let store: SessionStore

    var body: some View {
        let state = store.aggregateState.displayState
        let count = store.sessions.count

        Group {
            if state == .idle {
                // Idle: brand icon on a black capsule so it stands out on any menu bar color.
                Image(systemName: Theme.brandSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 28, height: 20)
                    .background(Capsule().fill(Theme.cardBackground))
                    .overlay(Capsule().strokeBorder(Theme.brand.opacity(0.9), lineWidth: 1))
                .transition(.opacity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: Theme.brandSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.brand)
                    if state == .replied {
                        ReplyIcon()
                    } else if state == .working {
                        Spinner() // something is in progress: small spinner, no card
                    } else {
                        StatusDot(state: state)
                    }
                    Text(Theme.pillLabel(for: state))
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                    if let top = store.sessions.first {
                        // Inline widget: project + waiting time right in the menu bar.
                        Text(Self.shortName(top.projectName))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                        if top.state.needsAttention {
                            Text(Theme.elapsed(since: top.stateSince, now: store.now))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(Theme.color(for: top.state))
                        }
                    }
                    if store.hasReply, state != .replied, !state.needsAttention {
                        ReplyIcon() // replied earlier this turn, agent keeps working
                    }
                    if count > 1 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 16, minHeight: 14)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .frame(height: 20)
                .background(Capsule().fill(Theme.cardBackground))
                .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity)) // slides out from the icon
                .overlay {
                    if state.needsAttention {
                        AttentionPulse() // your turn / approval: calm brand-colored breathing
                    } else {
                        Capsule().strokeBorder(Theme.brand.opacity(0.9), lineWidth: 1)
                    }
                }
            }
        }
        .fixedSize()
        .animation(.spring(duration: 0.25), value: state)
    }

    static func shortName(_ name: String, limit: Int = 18) -> String {
        name.count > limit ? String(name.prefix(limit - 1)) + "…" : name
    }
}

/// Slow breathing glow in the brand color (VS Code blue / Claude orange) while you are needed.
/// Calm on purpose: a 1.4 s fade, no hard blinking.
struct AttentionPulse: View {
    var body: some View {
        Capsule()
            .fill(Theme.brand.opacity(0.28))
            .overlay(Capsule().strokeBorder(Theme.brand, lineWidth: 1.5))
            .phaseAnimator([1.0, 0.3]) { content, level in
                content.opacity(level)
            } animation: { _ in .easeInOut(duration: 1.4) }
            .allowsHitTesting(false)
    }
}

/// Speech bubble: the agent sent a message, but it is not your turn (yet).
struct ReplyIcon: View {
    var body: some View {
        Image(systemName: Theme.replySymbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.brand)
            .help("Agenten har skickat ett svar men arbetar vidare")
    }
}

/// Small rotating arc in the brand color, shown in the pill while the agent works.
struct Spinner: View {
    var size: CGFloat = 9
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 1)
            .stroke(Theme.brand, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

struct StatusDot: View {
    let state: AgentState
    var size: CGFloat = 8

    var body: some View {
        let dot = Circle()
            .fill(Theme.color(for: state))
            .frame(width: size, height: size)
        if state.displayState == .working {
            dot.phaseAnimator([1.0, 0.3]) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            dot
        }
    }
}
