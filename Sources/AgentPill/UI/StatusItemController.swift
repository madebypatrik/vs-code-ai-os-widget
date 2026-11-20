import AppKit
import SwiftUI

/// Hosting view that lets clicks fall through to the status bar button.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// `NSStatusItem` with the SwiftUI pill. Left click toggles the card, right click shows the menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hostingView: PassthroughHostingView<PillView>
    private let store: SessionStore

    var onLeftClick: (() -> Void)?
    var buildMenu: (() -> NSMenu)?

    init(store: SessionStore) {
        self.store = store
        hostingView = PassthroughHostingView(rootView: PillView(store: store))
        super.init()

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("AgentPill")
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        resize()
        observe()
    }

    /// Screen rect of the button – anchor for the card.
    var buttonScreenRect: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func observe() {
        withObservationTracking {
            _ = store.aggregateState
            _ = store.sessions.first?.projectName
            _ = store.sessions.count
            _ = store.now // elapsed time in the pill can change its width
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                // Let SwiftUI update first, then size the item to the new pill.
                try? await Task.sleep(for: .milliseconds(30))
                self?.resize()
                self?.observe()
            }
        }
    }

    private func resize() {
        hostingView.layoutSubtreeIfNeeded()
        statusItem.length = max(22, hostingView.fittingSize.width + 6)
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick, let menu = buildMenu?(), let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else {
            onLeftClick?()
        }
    }
}
