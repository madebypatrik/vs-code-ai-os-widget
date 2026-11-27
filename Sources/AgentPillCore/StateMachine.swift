import Foundation

public struct StateMachineConfig: Sendable, Equatable {
    /// Time a tool may stay between PreToolUse and PostToolUse before we assume it waits for approval.
    public var approvalDelay: TimeInterval
    /// A `yourTurn` session without events for this long is removed. Nil = stays until the user acts.
    public var yourTurnTimeout: TimeInterval?
    /// Any session without events for this long is removed (crashed / closed windows).
    public var staleTimeout: TimeInterval
    /// Tools that never need approval and therefore never start the approval timer.
    public var autoApprovedTools: Set<String>
    /// Time after Stop during which further agent activity means it only sent an interim
    /// message and keeps working. 0 = Stop is always `yourTurn` right away.
    public var replyGraceDelay: TimeInterval

    public init(
        approvalDelay: TimeInterval = 3,
        replyGraceDelay: TimeInterval = 0,
        yourTurnTimeout: TimeInterval? = nil,
        staleTimeout: TimeInterval = 2 * 60 * 60,
        autoApprovedTools: Set<String> = []
    ) {
        self.approvalDelay = approvalDelay
        self.yourTurnTimeout = yourTurnTimeout
        self.staleTimeout = staleTimeout
        self.autoApprovedTools = autoApprovedTools
        self.replyGraceDelay = replyGraceDelay
    }
}

public struct StateTransition: Equatable, Sendable {
    public var sessionId: String
    public var from: AgentState
    public var to: AgentState
    /// The session after the transition, or nil if it was removed.
    public var session: Session?
}

/// Pure state logic from spec §6. Time is always passed in, so it is fully unit-testable.
public struct StateMachine: Sendable {
    public var config: StateMachineConfig
    public private(set) var sessions: [String: Session] = [:]
    /// Subagent session id → the session that started it. Subagents are not shown as sessions.
    public private(set) var parentOf: [String: String] = [:]

    public init(config: StateMachineConfig = StateMachineConfig()) {
        self.config = config
    }

    // MARK: - Queries

    /// Most urgent displayed state across sessions (`needsApproval` > `yourTurn` > `working` > `idle`).
    public var aggregateState: AgentState {
        sessions.values.map(\.state.displayState).max() ?? .idle
    }

    /// Sessions sorted by urgency, then by how long they have waited.
    public var orderedSessions: [Session] {
        sessions.values.sorted {
            if $0.state.displayState != $1.state.displayState {
                return $0.state.displayState > $1.state.displayState
            }
            if $0.stateSince != $1.stateSince { return $0.stateSince < $1.stateSince }
            return $0.id < $1.id
        }
    }

    public var attentionSessions: [Session] { orderedSessions.filter { $0.state.needsAttention } }

    /// True when some session has a message from the agent that is not a "your turn" yet:
    /// it just replied, or it replied and then kept working.
    public var hasReply: Bool {
        sessions.values.contains { $0.state == .replied || ($0.hasInterimReply && !$0.state.needsAttention) }
    }

    // MARK: - Events

    @discardableResult
    public mutating func handle(_ event: HookEvent, now: Date = Date()) -> [StateTransition] {
        if let parent = event.parentSessionId { parentOf[event.sessionId] = parent }
        if let parent = parentOf[event.sessionId] {
            return handleSubagent(event, parent: parent, now: now)
        }

        let kind = event.kind
        guard kind != .unknown else {
            sessions[event.sessionId]?.lastEventAt = now
            return []
        }

        var session = sessions[event.sessionId]
            ?? Session(id: event.sessionId, cwd: event.cwd ?? "", stateSince: now, lastEventAt: now)
        if let cwd = event.cwd, !cwd.isEmpty, cwd != session.cwd {
            session.cwd = cwd
            session.projectName = Session.projectName(for: cwd)
        }
        session.lastEventAt = now
        let previous = session.state

        switch kind {
        case .userPromptSubmit:
            Self.set(&session, to: .working, now: now)
            Self.clearTool(&session)
            session.hasInterimReply = false

        case .preToolUse:
            session.pendingToolCount += 1
            let summary = event.toolSummary
            let autoApproved = event.toolName.map { config.autoApprovedTools.contains($0) } ?? false
            Self.resumeAfterReply(&session, now: now)
            switch session.state {
            case .needsApproval:
                break // Still waiting for the user; keep showing the first blocked tool.
            case .toolPending:
                if !autoApproved, session.approvalDeadline == nil {
                    session.pendingTool = summary
                    session.approvalDeadline = now.addingTimeInterval(config.approvalDelay)
                }
            default:
                Self.set(&session, to: .toolPending, now: now)
                session.pendingTool = summary
                session.approvalDeadline = autoApproved ? nil : now.addingTimeInterval(config.approvalDelay)
            }

        case .postToolUse:
            session.pendingToolCount = max(0, session.pendingToolCount - 1)
            switch session.state {
            case .toolPending, .needsApproval:
                if session.pendingToolCount == 0 {
                    Self.set(&session, to: .working, now: now)
                    Self.clearTool(&session)
                }
            case .idle, .yourTurn, .replied:
                Self.resumeAfterReply(&session, now: now)
                Self.set(&session, to: .working, now: now)
                Self.clearTool(&session)
            case .working:
                break
            }

        case .stop:
            Self.clearTool(&session)
            if config.replyGraceDelay > 0, session.state != .yourTurn {
                Self.set(&session, to: .replied, now: now)
                session.yourTurnDeadline = now.addingTimeInterval(config.replyGraceDelay)
            } else {
                Self.set(&session, to: .yourTurn, now: now)
                session.hasInterimReply = false
            }

        case .unknown:
            break
        }

        sessions[session.id] = session
        guard previous != session.state else { return [] }
        return [StateTransition(sessionId: session.id, from: previous, to: session.state, session: session)]
    }

    /// Subagent events belong to the parent session. Only their tool calls matter (a subagent
    /// tool can wait for approval); their prompt and Stop say nothing about the user's turn.
    private mutating func handleSubagent(_ event: HookEvent, parent: String, now: Date) -> [StateTransition] {
        var transitions: [StateTransition] = []
        // A row created before the link was known (e.g. tool event before the subagent prompt).
        if let orphan = sessions.removeValue(forKey: event.sessionId) {
            transitions.append(StateTransition(sessionId: orphan.id, from: orphan.state, to: .idle, session: nil))
        }
        guard var session = sessions[parent] else { return transitions }
        session.lastEventAt = now
        sessions[parent] = session

        let busy: Set<AgentState> = [.working, .toolPending, .needsApproval]
        guard event.kind == .preToolUse || event.kind == .postToolUse, busy.contains(session.state) else {
            return transitions
        }
        var forwarded = event
        forwarded.sessionId = parent
        forwarded.parentSessionId = nil
        return transitions + handle(forwarded, now: now)
    }

    /// Advances timers. Call about once per second.
    @discardableResult
    public mutating func tick(now: Date = Date()) -> [StateTransition] {
        var transitions: [StateTransition] = []
        for id in sessions.keys.sorted() {
            guard var session = sessions[id] else { continue }
            let idleFor = now.timeIntervalSince(session.lastEventAt)

            let expired = session.state.needsAttention
                ? session.state == .yourTurn && config.yourTurnTimeout.map { idleFor >= $0 } == true
                : idleFor >= config.staleTimeout
            if expired {
                sessions[id] = nil
                parentOf = parentOf.filter { $0.value != id }
                transitions.append(StateTransition(sessionId: id, from: session.state, to: .idle, session: nil))
                continue
            }

            if session.state == .replied, let deadline = session.yourTurnDeadline, now >= deadline {
                session.state = .yourTurn // stateSince stays at Stop
                session.yourTurnDeadline = nil
                session.hasInterimReply = false
                sessions[id] = session
                transitions.append(StateTransition(sessionId: id, from: .replied, to: .yourTurn, session: session))
                continue
            }

            if session.state == .toolPending, let deadline = session.approvalDeadline, now >= deadline {
                session.state = .needsApproval // stateSince stays at PreToolUse
                session.approvalDeadline = nil
                sessions[id] = session
                transitions.append(StateTransition(sessionId: id, from: .toolPending, to: .needsApproval, session: session))
            }
        }
        return transitions
    }

    /// VS Code's Dock badge appeared: mark the most recently active running session as waiting.
    @discardableResult
    public mutating func dockBadgeAppeared(now: Date = Date()) -> [StateTransition] {
        let candidate = sessions.values
            .filter { $0.state == .working || $0.state == .toolPending }
            .max { $0.lastEventAt < $1.lastEventAt }
        guard var session = candidate else { return [] }
        let previous = session.state
        if previous != .toolPending { session.stateSince = now }
        session.state = .needsApproval
        session.approvalDeadline = nil
        sessions[session.id] = session
        return [StateTransition(sessionId: session.id, from: previous, to: .needsApproval, session: session)]
    }

    /// Removes a session (e.g. from a context menu). Returns the transition if it existed.
    @discardableResult
    public mutating func remove(sessionId: String) -> StateTransition? {
        guard let session = sessions.removeValue(forKey: sessionId) else { return nil }
        parentOf = parentOf.filter { $0.value != sessionId }
        return StateTransition(sessionId: sessionId, from: session.state, to: .idle, session: nil)
    }

    // MARK: - Helpers

    private static func set(_ session: inout Session, to state: AgentState, now: Date) {
        guard session.state != state else { return }
        session.state = state
        session.stateSince = now
    }

    /// Activity after Stop: the message was an interim reply and the agent keeps working.
    private static func resumeAfterReply(_ session: inout Session, now: Date) {
        guard session.state == .replied else { return }
        set(&session, to: .working, now: now)
        session.yourTurnDeadline = nil
        session.hasInterimReply = true
    }

    private static func clearTool(_ session: inout Session) {
        session.pendingTool = nil
        session.approvalDeadline = nil
        session.pendingToolCount = 0
    }
}
