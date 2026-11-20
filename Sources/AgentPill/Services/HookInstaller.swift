import Foundation

/// Writes `~/.agentpill/report.sh` and `~/.copilot/hooks/agentpill.json`, with backup and uninstall.
struct HookInstaller {
    static let marker = "AgentPill"

    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var scriptURL: URL { home.appendingPathComponent(".agentpill/report.sh") }
    var hooksURL: URL { home.appendingPathComponent(".copilot/hooks/agentpill.json") }

    var isInstalled: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: scriptURL.path) && fm.fileExists(atPath: hooksURL.path)
    }

    /// Port currently written in report.sh, if installed.
    var installedPort: Int? {
        guard let script = try? String(contentsOf: scriptURL, encoding: .utf8),
              let range = script.range(of: #"127\.0\.0\.1:(\d+)"#, options: .regularExpression)
        else { return nil }
        return Int(script[range].split(separator: ":").last ?? "")
    }

    func scriptContents(port: UInt16) -> String {
        """
        #!/bin/bash
        # \(Self.marker): skickar hook-payload till AgentPill. Får ALDRIG skriva till stdout.
        curl -s -m 1 -X POST \\
          -H "Content-Type: application/json" \\
          --data-binary @- \\
          http://127.0.0.1:\(port)/event >/dev/null 2>&1
        exit 0

        """
    }

    func hooksContents() -> String {
        let command = scriptURL.path
        let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"]
        let width = events.map(\.count).max()! + 3
        let lines = events.map { name -> String in
            let key = "\"\(name)\":".padding(toLength: width, withPad: " ", startingAt: 0)
            return "    \(key) [{ \"type\": \"command\", \"command\": \"\(command)\", \"timeoutSec\": 2 }]"
        }
        // PascalCase event names select the VS Code-compatible payload (hook_event_name, session_id, tool_input).
        return "{\n  \"version\": 1,\n  \"hooks\": {\n" + lines.joined(separator: ",\n") + "\n  }\n}\n"
    }

    func install(port: UInt16) throws {
        try write(scriptContents(port: port), to: scriptURL, isOurs: { $0.contains(Self.marker) })
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try write(hooksContents(), to: hooksURL, isOurs: { $0.contains("/.agentpill/report.sh") })
    }

    func uninstall() throws {
        for url in [hooksURL, scriptURL] {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            let backup = backupURL(for: url)
            if fm.fileExists(atPath: backup.path) { try fm.moveItem(at: backup, to: url) }
        }
        let dir = scriptURL.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    private func backupURL(for url: URL) -> URL { url.appendingPathExtension("bak") }

    /// Backs up a foreign file to `*.bak` (once) before overwriting it.
    private func write(_ contents: String, to url: URL, isOurs: (String) -> Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? String(contentsOf: url, encoding: .utf8), !isOurs(existing) {
            let backup = backupURL(for: url)
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: url, to: backup) }
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
