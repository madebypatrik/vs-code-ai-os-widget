import AppKit
import ApplicationServices

/// Polls VS Code's Dock tile badge (`AXStatusLabel`) once per second. Needs Accessibility permission.
@MainActor
final class DockBadgeWatcher {
    var onBadgeAppeared: (() -> Void)?
    var isEnabled: () -> Bool = { true }
    private(set) var currentBadge: String?
    private var timer: Timer?

    private static let dockItemTitles: Set<String> = [
        "Visual Studio Code", "Code", "Visual Studio Code - Insiders", "VSCodium",
    ]

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security › Accessibility.
    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func start() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard isEnabled(), Self.isTrusted else {
            currentBadge = nil
            return
        }
        let badge = Self.readBadge()
        let hadBadge = !(currentBadge ?? "").isEmpty
        let hasBadge = !(badge ?? "").isEmpty
        currentBadge = badge
        if hasBadge && !hadBadge { onBadgeAppeared?() }
    }

    static func readBadge() -> String? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        for list in children(of: dockElement) {
            for item in children(of: list) {
                guard let title = attribute(item, kAXTitleAttribute) as? String,
                      dockItemTitles.contains(title)
                else { continue }
                return attribute(item, "AXStatusLabel") as? String
            }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
