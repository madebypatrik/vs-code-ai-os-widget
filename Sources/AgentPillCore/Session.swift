import Foundation

/// Per-session agent state. Raw values encode urgency, so `max()` gives the most urgent state.
public enum AgentState: Int, Comparable, Sendable, CaseIterable {
    case idle, working, toolPending, yourTurn, needsApproval

    public static func < (lhs: AgentState, rhs: AgentState) -> Bool { lhs.rawValue < rhs.rawValue }

    /// What the UI shows: `toolPending` looks like `working` until the approval timer fires.
    public var displayState: AgentState { self == .toolPending ? .working : self }

    /// True for states that need the user (card auto-expands, notification is sent).
    public var needsAttention: Bool { self == .needsApproval || self == .yourTurn }
}

public struct Session: Identifiable, Equatable, Sendable {
    public let id: String
    public var cwd: String
    public var projectName: String
    public var state: AgentState
    public var pendingTool: ToolSummary?
    /// When the current (displayed) state started. Kept from PreToolUse when escalating to
    /// `needsApproval`, so the card shows the full waiting time.
    public var stateSince: Date
    public var lastEventAt: Date
    /// When a `toolPending` session escalates to `needsApproval`. Nil for auto-approved tools.
    public var approvalDeadline: Date?
    /// Number of PreToolUse events without a matching PostToolUse (parallel tool calls).
    public var pendingToolCount: Int

    public init(
        id: String,
        cwd: String,
        state: AgentState = .idle,
        pendingTool: ToolSummary? = nil,
        stateSince: Date,
        lastEventAt: Date,
        approvalDeadline: Date? = nil,
        pendingToolCount: Int = 0
    ) {
        self.id = id
        self.cwd = cwd
        self.projectName = Session.projectName(for: cwd)
        self.state = state
        self.pendingTool = pendingTool
        self.stateSince = stateSince
        self.lastEventAt = lastEventAt
        self.approvalDeadline = approvalDeadline
        self.pendingToolCount = pendingToolCount
    }

    public static func projectName(for cwd: String) -> String {
        guard !cwd.isEmpty else { return "Okänt projekt" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? cwd : name
    }
}
