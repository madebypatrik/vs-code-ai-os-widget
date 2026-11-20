import AppKit

/// Opens / focuses VS Code's Agents window via the `code` CLI.
@MainActor
enum VSCodeLauncher {
    static let bundleIdentifiers = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium"]

    static func isVSCode(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return bundleIdentifiers.contains(id)
    }

    static var isFrontmost: Bool { isVSCode(NSWorkspace.shared.frontmostApplication) }

    static var appURL: URL? {
        for id in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        }
        return nil
    }

    /// `code` CLI: common install locations, then inside the app bundle.
    static let codeCLI: URL? = {
        var candidates = ["/usr/local/bin/code", "/opt/homebrew/bin/code"]
        if let app = appURL {
            candidates.append(app.appendingPathComponent("Contents/Resources/app/bin/code").path)
        }
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }()

    /// Opens VS Code's Agents window, where the chat sessions live. (`code --agents <folder>` would
    /// start a *new* session, so no folder is passed.)
    static func open(cwd: String?) {
        if let cli = codeCLI {
            let process = Process()
            process.executableURL = cli
            process.arguments = ["--agents"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                return
            } catch {
                NSLog("AgentPill: failed to run code CLI: \(error.localizedDescription)")
            }
        }
        activateApp()
    }

    private static func activateApp() {
        if let running = NSWorkspace.shared.runningApplications.first(where: { isVSCode($0) }) {
            running.activate()
            return
        }
        guard let url = appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
