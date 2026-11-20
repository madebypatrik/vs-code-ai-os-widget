import AgentPillCore
import AppKit
import SwiftUI

/// Borderless, non-activating panel that shows the widget right under the pill.
final class CardPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // SwiftUI draws the shadow
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ActivityPanelController {
    let model = PanelModel()
    private let panel = CardPanel()
    private let hostingView: NSHostingView<WidgetContainer>
    private var outsideClickMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?

    /// Screen rect of the status item button, used as anchor.
    var anchorRect: () -> NSRect? = { nil }
    /// When true the small widget never closes by itself; "hide" only collapses the full card.
    var alwaysVisible: () -> Bool = { false }
    /// While true the card stays open: focus changes, outside clicks and state changes
    /// don't close it. Only a pill click or "Påminn om 5 min" hides it.
    var isPinned: () -> Bool = { false }
    private(set) var isShown = false
    /// True if the card opened by itself (it then also closes by itself).
    private(set) var openedAutomatically = false

    init(store: SessionStore, port: UInt16, onOpen: @escaping (Session?) -> Void, onSnooze: @escaping () -> Void) {
        let view = WidgetContainer(store: store, panel: model, port: port, onOpen: onOpen, onSnooze: onSnooze)
        hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView
        observeLayout(store: store)
    }

    /// Pill click. Always-visible mode: switch between small widget and full card.
    func toggle() {
        if alwaysVisible() {
            if !isShown {
                model.isExpanded = false
                show(automatically: false)
            } else {
                setExpanded(!model.isExpanded)
            }
            return
        }
        if isShown {
            hide()
        } else {
            model.isExpanded = true
            show(automatically: false)
        }
    }

    /// Collapses the full card back to the small widget (always-visible mode) or hides it.
    func dismiss() {
        guard !isPinned() else { return }
        if alwaysVisible() {
            setExpanded(false)
        } else {
            hide()
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard model.isExpanded != expanded else { return }
        model.isExpanded = expanded
        if expanded { installOutsideClickMonitor() } else { removeOutsideClickMonitor() }
        DispatchQueue.main.async { self.relayout() }
    }

    func show(automatically: Bool) {
        if alwaysVisible() {
            // Small widget is already there; it never expands by itself.
            guard !isShown else { return }
        } else {
            model.isExpanded = true
        }
        hideWorkItem?.cancel()
        if !isShown { openedAutomatically = automatically }
        else if !automatically { openedAutomatically = false }
        isShown = true
        relayout()
        panel.orderFrontRegardless()
        if model.isExpanded { installOutsideClickMonitor() }
        DispatchQueue.main.async { self.model.isVisible = true }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        openedAutomatically = false
        model.isVisible = false
        removeOutsideClickMonitor()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func relayout() {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        guard let anchor = anchorRect() else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = anchor.midX - size.width / 2
        if visible.width > 0 {
            x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        let y = anchor.minY - 4 - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    /// Re-layout when sessions change size of the card.
    private func observeLayout(store: SessionStore) {
        withObservationTracking {
            _ = store.sessions.count
            _ = store.aggregateState
            _ = model.isExpanded
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isShown { self.relayout() }
                self.observeLayout(store: store)
            }
        }
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // Global monitors only see clicks in *other* apps – exactly "click outside".
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }
}
