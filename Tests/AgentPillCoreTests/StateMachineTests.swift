import XCTest
@testable import AgentPillCore

final class StateMachineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let cwd = "/Users/dev/projects/my-app"

    private func event(_ name: String, session: String = "s1", tool: String? = nil, command: String? = nil) -> HookEvent {
        HookEvent(
            eventName: name,
            sessionId: session,
            cwd: cwd,
            toolName: tool,
            toolInput: command.map { .object(["command": .string($0)]) }
        )
    }

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testUserPromptSubmitStartsWorking() {
        var machine = StateMachine()
        let transitions = machine.handle(event("UserPromptSubmit"), now: t0)
        XCTAssertEqual(transitions.map(\.to), [.working])
        XCTAssertEqual(machine.sessions["s1"]?.state, .working)
        XCTAssertEqual(machine.sessions["s1"]?.projectName, "my-app")
        XCTAssertEqual(machine.aggregateState, .working)
    }

    func testPreThenPostReturnsToWorkingWithoutApproval() {
        var machine = StateMachine()
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "run_in_terminal", command: "ls"), now: at(1))
        XCTAssertEqual(machine.sessions["s1"]?.state, .toolPending)
        XCTAssertEqual(machine.aggregateState, .working, "toolPending is displayed as working")

        XCTAssertEqual(machine.tick(now: at(2)), [])
        machine.handle(event("PostToolUse", tool: "run_in_terminal"), now: at(2.5))
        XCTAssertEqual(machine.sessions["s1"]?.state, .working)
        XCTAssertNil(machine.sessions["s1"]?.pendingTool)
        XCTAssertEqual(machine.tick(now: at(10)), [])
    }

    func testApprovalTimerEscalatesToNeedsApproval() {
        var machine = StateMachine(config: .init(approvalDelay: 3))
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "run_in_terminal", command: "npm run build"), now: at(1))

        XCTAssertEqual(machine.tick(now: at(3.9)), [])
        let transitions = machine.tick(now: at(4))
        XCTAssertEqual(transitions.map(\.to), [.needsApproval])
        let session = machine.sessions["s1"]!
        XCTAssertEqual(session.state, .needsApproval)
        XCTAssertEqual(session.stateSince, at(1), "waiting time counts from PreToolUse")
        XCTAssertEqual(session.pendingTool?.displayText, "Vill köra `npm run build`")
        XCTAssertEqual(machine.aggregateState, .needsApproval)

        // Approved → tool runs → PostToolUse
        let back = machine.handle(event("PostToolUse", tool: "run_in_terminal"), now: at(20))
        XCTAssertEqual(back.map(\.to), [.working])
    }

    func testAutoApprovedToolsNeverEscalate() {
        var machine = StateMachine(config: .init(approvalDelay: 3, autoApprovedTools: ["read_file"]))
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "read_file"), now: at(1))
        XCTAssertEqual(machine.tick(now: at(60)), [])
        XCTAssertEqual(machine.sessions["s1"]?.state, .toolPending)
    }

    func testParallelToolsWaitForAllPostToolUse() {
        var machine = StateMachine(config: .init(approvalDelay: 3, autoApprovedTools: ["read_file"]))
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "read_file"), now: at(1))
        machine.handle(event("PreToolUse", tool: "run_in_terminal", command: "rm -rf dist"), now: at(1.1))
        machine.handle(event("PostToolUse", tool: "read_file"), now: at(1.2))
        XCTAssertEqual(machine.sessions["s1"]?.state, .toolPending)
        XCTAssertEqual(machine.tick(now: at(5)).map(\.to), [.needsApproval])
        XCTAssertEqual(machine.sessions["s1"]?.pendingTool?.detail, "rm -rf dist")
        machine.handle(event("PostToolUse", tool: "run_in_terminal"), now: at(9))
        XCTAssertEqual(machine.sessions["s1"]?.state, .working)
    }

    func testStopGivesYourTurnFromAnyState() {
        for setup in [["UserPromptSubmit"], ["UserPromptSubmit", "PreToolUse"], []] {
            var machine = StateMachine()
            for name in setup { machine.handle(event(name, tool: "x"), now: t0) }
            let transitions = machine.handle(event("Stop"), now: at(5))
            XCTAssertEqual(transitions.last?.to, .yourTurn)
            XCTAssertEqual(machine.sessions["s1"]?.stateSince, at(5))
        }
    }

    func testUserPromptSubmitFromYourTurnAndNeedsApproval() {
        var machine = StateMachine()
        machine.handle(event("Stop"), now: t0)
        XCTAssertEqual(machine.handle(event("UserPromptSubmit"), now: at(1)).map(\.to), [.working])

        machine.handle(event("PreToolUse", tool: "t"), now: at(2))
        machine.tick(now: at(10))
        XCTAssertEqual(machine.sessions["s1"]?.state, .needsApproval)
        XCTAssertEqual(machine.handle(event("UserPromptSubmit"), now: at(11)).map(\.to), [.working])
    }

    func testYourTurnStaysByDefault() {
        var machine = StateMachine()
        machine.handle(event("Stop"), now: t0)
        XCTAssertEqual(machine.tick(now: at(24 * 60 * 60)), [])
        XCTAssertEqual(machine.aggregateState, .yourTurn)
    }

    func testYourTurnTimesOutAfter30Minutes() {
        var machine = StateMachine(config: .init(yourTurnTimeout: 30 * 60))
        machine.handle(event("Stop"), now: t0)
        XCTAssertEqual(machine.tick(now: at(30 * 60 - 1)), [])
        let removed = machine.tick(now: at(30 * 60))
        XCTAssertEqual(removed.map(\.to), [.idle])
        XCTAssertNil(removed.first?.session)
        XCTAssertTrue(machine.sessions.isEmpty)
        XCTAssertEqual(machine.aggregateState, .idle)
    }

    func testStaleWorkingSessionIsRemoved() {
        var machine = StateMachine(config: .init(staleTimeout: 100))
        machine.handle(event("UserPromptSubmit"), now: t0)
        XCTAssertEqual(machine.tick(now: at(99)), [])
        XCTAssertEqual(machine.tick(now: at(100)).map(\.to), [.idle])
    }

    func testDockBadgeMarksMostRecentRunningSession() {
        var machine = StateMachine()
        machine.handle(event("UserPromptSubmit", session: "a"), now: t0)
        machine.handle(event("UserPromptSubmit", session: "b"), now: at(1))
        machine.handle(event("Stop", session: "c"), now: at(2))
        let transitions = machine.dockBadgeAppeared(now: at(3))
        XCTAssertEqual(transitions.map(\.sessionId), ["b"])
        XCTAssertEqual(machine.sessions["b"]?.state, .needsApproval)
        XCTAssertEqual(machine.sessions["a"]?.state, .working)
    }

    func testDockBadgeWithoutRunningSessionDoesNothing() {
        var machine = StateMachine()
        machine.handle(event("Stop"), now: t0)
        XCTAssertEqual(machine.dockBadgeAppeared(now: at(1)), [])
    }

    func testPriorityAcrossSessions() {
        var machine = StateMachine(config: .init(approvalDelay: 3))
        machine.handle(event("UserPromptSubmit", session: "a"), now: t0)
        XCTAssertEqual(machine.aggregateState, .working)
        machine.handle(event("Stop", session: "b"), now: at(1))
        XCTAssertEqual(machine.aggregateState, .yourTurn)
        machine.handle(event("PreToolUse", session: "a", tool: "t"), now: at(2))
        XCTAssertEqual(machine.aggregateState, .yourTurn)
        machine.tick(now: at(6))
        XCTAssertEqual(machine.aggregateState, .needsApproval)
        XCTAssertEqual(machine.orderedSessions.map(\.id), ["a", "b"])
        XCTAssertEqual(machine.attentionSessions.count, 2)
    }

    func testUnknownEventsOnlyRefreshActivity() {
        var machine = StateMachine()
        machine.handle(event("Stop"), now: t0)
        XCTAssertEqual(machine.handle(event("SessionStart"), now: at(29 * 60)), [])
        XCTAssertEqual(machine.tick(now: at(31 * 60)), [], "unknown event refreshed lastEventAt")
        XCTAssertEqual(machine.handle(event("SessionStart", session: "new"), now: at(1)), [])
        XCTAssertNil(machine.sessions["new"])
    }

    func testNoTransitionWhenStateUnchanged() {
        var machine = StateMachine()
        machine.handle(event("UserPromptSubmit"), now: t0)
        XCTAssertEqual(machine.handle(event("UserPromptSubmit"), now: at(1)), [])
        XCTAssertEqual(machine.sessions["s1"]?.stateSince, t0)
    }

    // MARK: - Interim replies (Stop, then the agent keeps working)

    private func graceMachine() -> StateMachine {
        StateMachine(config: .init(replyGraceDelay: 8, autoApprovedTools: ["read_file"]))
    }

    func testStopWithGraceIsRepliedNotYourTurn() {
        var machine = graceMachine()
        machine.handle(event("UserPromptSubmit"), now: t0)
        let transitions = machine.handle(event("Stop"), now: at(5))
        XCTAssertEqual(transitions.map(\.to), [.replied])
        XCTAssertFalse(AgentState.replied.needsAttention)
        XCTAssertTrue(machine.attentionSessions.isEmpty)
        XCTAssertTrue(machine.hasReply)
        XCTAssertEqual(machine.aggregateState, .replied)
    }

    func testRepliedBecomesYourTurnAfterGrace() {
        var machine = graceMachine()
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("Stop"), now: at(5))
        XCTAssertEqual(machine.tick(now: at(12.9)), [])
        let transitions = machine.tick(now: at(13))
        XCTAssertEqual(transitions.map(\.to), [.yourTurn])
        XCTAssertEqual(machine.sessions["s1"]?.stateSince, at(5), "waiting time counts from Stop")
        XCTAssertFalse(machine.hasReply)
        XCTAssertEqual(machine.attentionSessions.map(\.id), ["s1"])
    }

    func testActivityAfterStopMeansInterimReply() {
        for next in ["PreToolUse", "PostToolUse"] {
            var machine = graceMachine()
            machine.handle(event("UserPromptSubmit"), now: t0)
            machine.handle(event("Stop"), now: at(5))
            machine.handle(event(next, tool: "read_file"), now: at(9))
            XCTAssertEqual(machine.sessions["s1"]?.state.displayState, .working, next)
            XCTAssertEqual(machine.sessions["s1"]?.stateSince, at(9), next)
            XCTAssertEqual(machine.sessions["s1"]?.hasInterimReply, true, next)
            XCTAssertTrue(machine.hasReply, next)
            XCTAssertEqual(machine.tick(now: at(20)).map(\.to), [], "grace timer is cancelled")
        }
    }

    func testInterimReplyClearedByPromptAndFinalStop() {
        var machine = graceMachine()
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("Stop"), now: at(1))
        machine.handle(event("PostToolUse"), now: at(2))
        machine.handle(event("Stop"), now: at(30))
        XCTAssertEqual(machine.sessions["s1"]?.state, .replied)
        machine.tick(now: at(40))
        XCTAssertEqual(machine.sessions["s1"]?.state, .yourTurn)
        XCTAssertEqual(machine.sessions["s1"]?.hasInterimReply, false)

        machine.handle(event("Stop"), now: at(50))
        XCTAssertEqual(machine.sessions["s1"]?.state, .yourTurn, "a second Stop keeps your turn")

        machine.handle(event("UserPromptSubmit"), now: at(60))
        machine.handle(event("Stop"), now: at(61))
        machine.handle(event("PreToolUse", tool: "t"), now: at(62))
        machine.handle(event("UserPromptSubmit"), now: at(70))
        XCTAssertEqual(machine.sessions["s1"]?.hasInterimReply, false)
        XCTAssertFalse(machine.hasReply)
    }

    func testRepliedRanksAboveWorkingBelowYourTurn() {
        var machine = graceMachine()
        machine.handle(event("UserPromptSubmit", session: "a"), now: t0)
        machine.handle(event("Stop", session: "b"), now: t0)
        XCTAssertEqual(machine.aggregateState, .replied)
        machine.handle(event("Stop", session: "c"), now: t0)
        machine.tick(now: at(10))
        XCTAssertEqual(machine.aggregateState, .yourTurn)
    }
}
