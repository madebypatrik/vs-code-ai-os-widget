import AgentPillCore
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var store = SessionStore(settings: settings)
    private lazy var server = EventServer(port: settings.validPort)
    private let notifier = Notifier()
    private let focusWatcher = FocusWatcher()
    private let dockWatcher = DockBadgeWatcher()
    private var statusController: StatusItemController!
    private var panelController: ActivityPanelController!
    private var windows: [String: NSWindow] = [:]

    private struct Snooze {
        var state: AgentState
        var stateSince: Date
        var until: Date
    }
    private var snoozes: [String: Snooze] = [:]
    /// An automatically shown card folds back after this long; the pill keeps signalling.
    private let autoShowDuration: Duration = .seconds(10)
    private var autoHideTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(store: store)
        panelController = ActivityPanelController(
            store: store,
            port: settings.validPort,
            onOpen: { [weak self] session in self?.open(session) },
            onSnooze: { [weak self] in self?.snooze(minutes: 5) }
        )
        panelController.model.onClose = { [weak self] in self?.snooze(minutes: 2) }
        panelController.anchorRect = { [weak self] in self?.statusController.buttonScreenRect }
        panelController.alwaysVisible = { [weak self] in self?.settings.alwaysVisible ?? false }
        // Outside clicks and app switches never close the card. An automatically shown card
        // folds back after 10 s (the pill keeps pulsing); a card opened from the pill stays.
        panelController.isPinned = { true }
        observeAlwaysVisible()
        if settings.alwaysVisible {
            // Wait one run loop so the status item has a position on screen.
            DispatchQueue.main.async { self.panelController.show(automatically: false) }
        }
        statusController.onLeftClick = { [weak self] in self?.panelController.toggle() }
        statusController.buildMenu = { [weak self] in self?.makeMenu() ?? NSMenu() }

        store.onTransitions = { [weak self] in self?.handle($0) }
        store.onTick = { [weak self] in self?.checkSnoozes(now: $0) }
        store.start()

        server.onEvent = { [weak self] in self?.store.ingest($0) }
        server.stateProvider = { [weak self] in self?.store.stateJSON() ?? "{}" }
        server.onStatusChange = { status in
            if case .failed(let reason) = status { NSLog("AgentPill: server failed: \(reason)") }
        }
        server.start()

        notifier.onOpen = { cwd in VSCodeLauncher.open(cwd: cwd) }

        // You switched to VS Code: the chats are in view, so fold away a card that opened by itself.
        focusWatcher.onVSCodeActivated = { [weak self] in
            guard let self, self.panelController.openedAutomatically else { return }
            self.panelController.hide()
        }
        focusWatcher.start()

        dockWatcher.isEnabled = { [weak self] in self?.settings.dockBadgeEnabled ?? false }
        dockWatcher.onBadgeAppeared = { [weak self] in self?.store.dockBadgeAppeared() }
        dockWatcher.start()

        if !settings.didCompleteOnboarding {
            settings.launchAtLogin = true // on by default (spec §8)
            showOnboarding()
        }
    }

    /// Settings toggle: show the small widget immediately, or hide it.
    private func observeAlwaysVisible() {
        withObservationTracking {
            _ = settings.alwaysVisible
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.settings.alwaysVisible {
                    self.panelController.show(automatically: false)
                } else {
                    self.panelController.hide()
                }
                self.observeAlwaysVisible()
            }
        }
    }

    // MARK: - State changes

    private func handle(_ transitions: [StateTransition]) {
        for transition in transitions {
            guard let session = transition.session else {
                snoozes[transition.sessionId] = nil
                notifier.removeDelivered(for: transition.sessionId)
                continue
            }
            if !session.state.needsAttention {
                snoozes[session.id] = nil
                notifier.removeDelivered(for: session.id)
                continue
            }
            snoozes[session.id] = nil
            // The card shows even when VS Code is in front – it stays while it is your turn.
            if settings.autoExpand { showBriefly() }
            if !VSCodeLauncher.isFrontmost {
                notifier.notify(session, playSound: session.state == .needsApproval && settings.soundEnabled)
            }
        }

        // Auto-opened card closes itself when nothing needs the user anymore.
        if store.attentionSessions.isEmpty, panelController.openedAutomatically {
            panelController.dismiss()
        }
    }

    /// Shows the card for a few seconds. Opening it from the pill in the meantime keeps it open.
    private func showBriefly() {
        // VS Code is in front: you already see the chats, so only the pulsing pill signals.
        guard !VSCodeLauncher.isFrontmost else { return }
        panelController.show(automatically: true)
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.autoShowDuration)
            guard !Task.isCancelled, self.panelController.openedAutomatically else { return }
            self.panelController.hide()
        }
    }

    /// Hides the card; it comes back after `minutes` if a session still waits for you unchanged.
    private func snooze(minutes: Double) {
        let until = Date().addingTimeInterval(minutes * 60)
        for session in store.attentionSessions {
            snoozes[session.id] = Snooze(state: session.state, stateSince: session.stateSince, until: until)
        }
        panelController.hide() // explicit user choice, overrides the pin
    }

    private func checkSnoozes(now: Date) {
        for (id, snooze) in snoozes where now >= snooze.until {
            snoozes[id] = nil
            guard let session = store.machine.sessions[id],
                  session.state == snooze.state,
                  session.stateSince == snooze.stateSince
            else { continue }
            showBriefly()
            if !VSCodeLauncher.isFrontmost {
                notifier.notify(session, playSound: session.state == .needsApproval && settings.soundEnabled)
            }
        }
    }

    private func open(_ session: Session?) {
        snooze(minutes: 5) // hides the card; back in 5 min if still waiting
        VSCodeLauncher.open(cwd: session?.cwd)
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem(title: serverStatusText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(item("Inställningar…", #selector(showSettings), key: ","))
        menu.addItem(item("Introduktion…", #selector(showOnboardingAction)))
        if HookInstaller().isInstalled {
            menu.addItem(item("Avinstallera hooks", #selector(uninstallHooksAction)))
        } else {
            menu.addItem(item("Installera hooks", #selector(installHooksAction)))
        }
        if !store.sessions.isEmpty {
            menu.addItem(item("Rensa sessioner", #selector(clearSessions)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Avsluta AgentPill", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private var serverStatusText: String {
        switch server.status {
        case .listening: "Lyssnar på 127.0.0.1:\(server.port)"
        case .starting: "Startar server…"
        case .stopped: "Servern är stoppad"
        case .failed(let reason): "Serverfel: \(reason)"
        }
    }

    @objc private func showSettings() {
        let view = SettingsView(
            settings: settings,
            runningPort: server.port,
            serverStatus: { [weak self] in self?.serverStatusText ?? "" },
            installHooks: { [weak self] in self?.installHooks() },
            uninstallHooks: { [weak self] in self?.uninstallHooks() }
        )
        showWindow(id: "settings", title: "AgentPill – Inställningar", view: view)
    }

    @objc private func showOnboardingAction() { showOnboarding() }

    private func showOnboarding() {
        let view = OnboardingView(
            settings: settings,
            installHooks: { [weak self] in self?.installHooks() },
            requestNotifications: { [weak self] in await self?.notifier.requestAuthorization() ?? false },
            onDone: { [weak self] in
                self?.settings.didCompleteOnboarding = true
                self?.windows["onboarding"]?.close()
            }
        )
        showWindow(id: "onboarding", title: "AgentPill", view: view)
    }

    @objc private func installHooksAction() {
        if let error = installHooks() { alert("Kunde inte installera hooks", error) }
    }

    @objc private func uninstallHooksAction() {
        if let error = uninstallHooks() { alert("Kunde inte avinstallera hooks", error) }
    }

    @objc private func clearSessions() {
        for session in store.sessions { store.remove(session.id) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func installHooks() -> String? {
        do {
            try HookInstaller().install(port: settings.validPort)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func uninstallHooks() -> String? {
        do {
            try HookInstaller().uninstall()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Windows

    private func showWindow(id: String, title: String, view: some View) {
        if let window = windows[id] {
            window.contentViewController = NSHostingController(rootView: view)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
