import Foundation

/// Minimal, tolerant JSON value used to decode hook payloads whose shape may change.
public enum JSONValue: Decodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    /// String representation for scalar values (numbers are formatted without trailing `.0`).
    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    /// Compact single-line description, used as a last-resort summary of `tool_input`.
    public var compactDescription: String {
        switch self {
        case .string(let value): return value
        case .number, .bool: return stringValue ?? ""
        case .null: return "null"
        case .array(let values): return "[" + values.map(\.compactDescription).joined(separator: ", ") + "]"
        case .object(let dict):
            let parts = dict.keys.sorted().map { "\($0): \(dict[$0]!.compactDescription)" }
            return "{" + parts.joined(separator: ", ") + "}"
        }
    }
}
