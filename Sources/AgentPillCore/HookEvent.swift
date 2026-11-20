import Foundation

/// Short description of the tool the agent wants to run.
public struct ToolSummary: Sendable, Equatable {
    public var name: String
    /// The most relevant argument (command, file path, query …), single line, max ~80 chars.
    public var detail: String?
    /// True when `detail` is a shell command (rendered as "Vill köra `cmd`").
    public var isCommand: Bool

    public init(name: String, detail: String?, isCommand: Bool) {
        self.name = name
        self.detail = detail
        self.isCommand = isCommand
    }

    /// Same as `displayText` but without Markdown backticks (rows, notifications).
    public var plainText: String {
        if isCommand, let detail { return "Vill köra \(detail)" }
        return displayText
    }

    /// Swedish one-liner, e.g. "Vill köra `npm run build`" or "Vill använda read_file · src/app.ts".
    public var displayText: String {
        if isCommand, let detail { return "Vill köra `\(detail)`" }
        if let detail, !detail.isEmpty { return "Vill använda \(name) · \(detail)" }
        return "Vill använda \(name)"
    }
}

/// A hook payload posted by `report.sh`. Decoding is tolerant: unknown fields are ignored and
/// both snake_case (VS Code) and camelCase (Copilot CLI) field names are accepted.
public struct HookEvent: Decodable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case userPromptSubmit, preToolUse, postToolUse, stop, unknown

        init(name: String) {
            switch name.lowercased() {
            case "userpromptsubmit", "userpromptsubmitted": self = .userPromptSubmit
            case "pretooluse": self = .preToolUse
            case "posttooluse": self = .postToolUse
            case "stop", "agentstop", "sessionend": self = .stop
            default: self = .unknown
            }
        }
    }

    public static let maxDetailLength = 80

    public var eventName: String
    public var sessionId: String
    public var cwd: String?
    public var toolName: String?
    public var toolInput: JSONValue?
    public var timestamp: Date?
    public var stopReason: String?

    public var kind: Kind { Kind(name: eventName) }

    public init(
        eventName: String,
        sessionId: String,
        cwd: String? = nil,
        toolName: String? = nil,
        toolInput: JSONValue? = nil,
        timestamp: Date? = nil,
        stopReason: String? = nil
    ) {
        self.eventName = eventName
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.toolInput = toolInput
        self.timestamp = timestamp
        self.stopReason = stopReason
    }

    public static func decode(_ data: Data) throws -> HookEvent {
        try JSONDecoder().decode(HookEvent.self, from: data)
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)

        func value(_ keys: String...) -> JSONValue? {
            for key in keys {
                if let found = try? container.decodeIfPresent(JSONValue.self, forKey: AnyKey(key)), found != .null {
                    return found
                }
            }
            return nil
        }

        guard let name = value("hook_event_name", "hookEventName", "event_name", "eventName", "event")?.stringValue,
              !name.isEmpty
        else {
            throw DecodingError.keyNotFound(
                AnyKey("hook_event_name"),
                .init(codingPath: [], debugDescription: "Payload has no hook event name")
            )
        }

        let cwd = value("cwd", "workspace", "workspaceFolder")?.stringValue
        eventName = name
        self.cwd = cwd
        sessionId = value("session_id", "sessionId", "conversation_id", "conversationId")?.stringValue
            ?? cwd
            ?? "default"
        toolName = value("tool_name", "toolName")?.stringValue
        toolInput = value("tool_input", "toolInput", "toolArgs", "tool_args")
        stopReason = value("stop_reason", "stopReason", "reason")?.stringValue
        timestamp = value("timestamp", "time").flatMap(Self.parseDate)
    }

    static func parseDate(_ value: JSONValue) -> Date? {
        if case .number(let number) = value {
            // Milliseconds if it looks like a JS timestamp, otherwise seconds.
            return Date(timeIntervalSince1970: number > 1e12 ? number / 1000 : number)
        }
        guard let string = value.stringValue else { return nil }
        if let number = Double(string) { return parseDate(.number(number)) }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    // MARK: - Tool summary

    private static let commandKeys = ["command", "commandLine", "command_line", "cmd", "script"]
    private static let detailKeys = [
        "filePath", "file_path", "path", "uri", "url", "query", "pattern", "includePattern",
        "dirPath", "explanation", "description", "goal", "input",
    ]

    /// Summary of the pending tool call, or nil if the event has no tool.
    public var toolSummary: ToolSummary? {
        guard let toolName, !toolName.isEmpty else { return nil }

        var input = toolInput
        // Copilot CLI sends tool args as a JSON-encoded string.
        if case .string(let raw) = input,
           let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(JSONValue.self, from: data),
           case .object = parsed {
            input = parsed
        }

        switch input {
        case .object(let dict):
            for key in Self.commandKeys {
                if let command = dict[key]?.stringValue, !command.isEmpty {
                    return ToolSummary(name: toolName, detail: Self.shorten(command), isCommand: true)
                }
            }
            for key in Self.detailKeys {
                if let detail = dict[key]?.stringValue, !detail.isEmpty {
                    return ToolSummary(name: toolName, detail: Self.shorten(detail), isCommand: false)
                }
            }
            let fallback = input?.compactDescription ?? ""
            return ToolSummary(name: toolName, detail: dict.isEmpty ? nil : Self.shorten(fallback), isCommand: false)
        case .string(let text):
            return ToolSummary(name: toolName, detail: text.isEmpty ? nil : Self.shorten(text), isCommand: false)
        case .none, .null:
            return ToolSummary(name: toolName, detail: nil, isCommand: false)
        case .some(let other):
            return ToolSummary(name: toolName, detail: Self.shorten(other.compactDescription), isCommand: false)
        }
    }

    /// Collapses whitespace/newlines and truncates to `maxDetailLength` characters.
    public static func shorten(_ text: String, limit: Int = maxDetailLength) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }
}
