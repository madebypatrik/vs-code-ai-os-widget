import Foundation

/// Tiny HTTP/1.1 request parser – just enough for `POST /event` from curl.
public enum HTTPRequestParser {
    public struct Request: Equatable, Sendable {
        public var method: String
        public var path: String
        public var headers: [String: String] // lowercased names
        public var body: Data
    }

    public enum Result: Equatable, Sendable {
        case incomplete
        case complete(Request)
        case invalid(String)
    }

    public static let maxBodySize = 1_048_576

    public static func parse(_ data: Data) -> Result {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return data.count > 16_384 ? .invalid("Headers too large") : .incomplete
        }
        guard let headerText = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid("Headers are not UTF-8")
        }
        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid("Malformed request line") }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid("Bad Content-Length") }
        guard length <= maxBodySize else { return .invalid("Body too large") }

        let bodyStart = headerEnd.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= length else { return .incomplete }
        let body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: length)])

        return .complete(Request(
            method: String(requestLine[0]).uppercased(),
            path: String(requestLine[1]),
            headers: headers,
            body: body
        ))
    }

    public static func response(status: Int, reason: String, body: String = "") -> Data {
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(bytes.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data(head.utf8) + bytes
    }
}
