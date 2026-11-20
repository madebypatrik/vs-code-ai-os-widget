import AppKit

/// Calls `onVSCodeActivated` when VS Code becomes the active app.
@MainActor
final class FocusWatcher {
    var onVSCodeActivated: (() -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleId = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let bundleId, VSCodeLauncher.bundleIdentifiers.contains(bundleId) else { return }
                self?.onVSCodeActivated?()
            }
        }
    }
}
