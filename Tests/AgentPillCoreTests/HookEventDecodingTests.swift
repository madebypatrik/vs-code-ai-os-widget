import XCTest
@testable import AgentPillCore

final class HookEventDecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> HookEvent {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try HookEvent.decode(Data(contentsOf: url))
    }

    func testPreToolUseTerminal() throws {
        let event = try fixture("pretooluse-terminal")
        XCTAssertEqual(event.kind, .preToolUse)
        XCTAssertEqual(event.sessionId, "8f2c1a4e-0b7d-4c5e-9a31-2d6f0e8b7c11")
        XCTAssertEqual(event.cwd, "/Users/dev/projects/my-app")
        XCTAssertEqual(event.toolName, "run_in_terminal")
        XCTAssertEqual(event.toolSummary, ToolSummary(name: "run_in_terminal", detail: "npm run build", isCommand: true))
        XCTAssertNotNil(event.timestamp)
    }

    func testPostToolUseWithMillisecondTimestamp() throws {
        let event = try fixture("posttooluse")
        XCTAssertEqual(event.kind, .postToolUse)
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 1_795_194_723.412))
    }

    func testStop() throws {
        let event = try fixture("stop")
        XCTAssertEqual(event.kind, .stop)
        XCTAssertEqual(event.stopReason, "end_turn")
        XCTAssertNil(event.toolSummary)
    }

    func testSubagentLinksToParentViaTranscriptPath() throws {
        let event = try fixture("subagent-stop")
        XCTAssertEqual(event.kind, .stop)
        XCTAssertEqual(event.parentSessionId, "8f2c1a4e-0b7d-4c5e-9a31-2d6f0e8b7c11")
    }

    func testOwnTranscriptPathIsNotAParent() throws {
        let json = #"""
        {"hook_event_name":"Stop","session_id":"abc","transcript_path":"/Users/dev/.copilot/session-state/abc/events.jsonl"}
        """#
        XCTAssertNil(try HookEvent.decode(Data(json.utf8)).parentSessionId)
        XCTAssertNil(try fixture("stop").parentSessionId)
    }

    func testCamelCaseParentAgentId() throws {
        let json = #"""
        {"hookEventName":"agentStop","sessionId":"child","agentId":"child","parentAgentId":"parent"}
        """#
        XCTAssertEqual(try HookEvent.decode(Data(json.utf8)).parentSessionId, "parent")
    }

    func testUserPromptSubmit() throws {
        XCTAssertEqual(try fixture("userpromptsubmit").kind, .userPromptSubmit)
    }

    func testCopilotCLICamelCaseAndStringArgs() throws {
        let event = try fixture("copilot-cli-pretooluse")
        XCTAssertEqual(event.kind, .preToolUse)
        XCTAssertEqual(event.sessionId, "cli-42")
        XCTAssertEqual(event.toolSummary?.detail, "git status && echo done")
        XCTAssertEqual(event.toolSummary?.isCommand, true)
        XCTAssertEqual(event.timestamp, Date(timeIntervalSince1970: 1_795_194_723))
    }

    func testMissingSessionFallsBackToCwd() throws {
        let event = try HookEvent.decode(Data(#"{"hook_event_name":"Stop","cwd":"/a/b"}"#.utf8))
        XCTAssertEqual(event.sessionId, "/a/b")
    }

    func testMissingEventNameThrows() {
        XCTAssertThrowsError(try HookEvent.decode(Data(#"{"session_id":"x"}"#.utf8)))
    }

    func testFilePathSummaryAndTruncation() throws {
        let long = String(repeating: "a", count: 200)
        let json = #"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"read_file","tool_input":{"filePath":"\#(long)"}}"#
        let summary = try XCTUnwrap(HookEvent.decode(Data(json.utf8)).toolSummary)
        XCTAssertFalse(summary.isCommand)
        XCTAssertEqual(summary.detail?.count, HookEvent.maxDetailLength)
        XCTAssertTrue(summary.detail!.hasSuffix("…"))
        XCTAssertTrue(summary.displayText.hasPrefix("Vill använda read_file · "))
    }

    func testHTTPParser() {
        let body = #"{"hook_event_name":"Stop"}"#
        let raw = "POST /event HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let data = Data(raw.utf8)
        XCTAssertEqual(HTTPRequestParser.parse(data.prefix(20)), .incomplete)
        XCTAssertEqual(HTTPRequestParser.parse(data.dropLast(3)), .incomplete)
        guard case .complete(let request) = HTTPRequestParser.parse(data) else { return XCTFail() }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/event")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), body)
        XCTAssertEqual(request.headers["host"], "127.0.0.1")
    }
}
