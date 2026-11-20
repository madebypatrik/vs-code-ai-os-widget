import AgentPillCore
import Foundation
import Observation
import ServiceManagement

/// User settings, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let defaultPort = 47823
    static let defaultAutoApprovedTools = [
        "read_file", "list_dir", "file_search", "grep_search", "semantic_search",
        "get_errors", "get_changed_files", "manage_todo_list", "test_search",
    ].joined(separator: ", ")

    private enum Key {
        static let port = "port"
        static let approvalDelay = "approvalDelay"
        static let soundEnabled = "soundEnabled"
        static let autoExpand = "autoExpand"
        static let dockBadgeEnabled = "dockBadgeEnabled"
        static let autoApprovedTools = "autoApprovedTools"
        static let didOnboard = "didCompleteOnboarding"
        static let alwaysVisible = "alwaysVisible"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var port: Int { didSet { defaults.set(port, forKey: Key.port) } }
    var approvalDelay: Double { didSet { defaults.set(approvalDelay, forKey: Key.approvalDelay) } }
    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }
    var autoExpand: Bool { didSet { defaults.set(autoExpand, forKey: Key.autoExpand) } }
    var dockBadgeEnabled: Bool { didSet { defaults.set(dockBadgeEnabled, forKey: Key.dockBadgeEnabled) } }
    var autoApprovedToolsText: String { didSet { defaults.set(autoApprovedToolsText, forKey: Key.autoApprovedTools) } }
    var didCompleteOnboarding: Bool { didSet { defaults.set(didCompleteOnboarding, forKey: Key.didOnboard) } }
    /// Floating small widget under the pill all the time (off: info lives in the pill, card drops down when needed).
    var alwaysVisible: Bool { didSet { defaults.set(alwaysVisible, forKey: Key.alwaysVisible) } }

    /// Backed by `SMAppService`, so it reflects what System Settings says.
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("AgentPill: launch at login failed: \(error.localizedDescription)")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.port: Self.defaultPort,
            Key.approvalDelay: 3.0,
            Key.soundEnabled: true,
            Key.autoExpand: true,
            Key.dockBadgeEnabled: true,
            Key.autoApprovedTools: Self.defaultAutoApprovedTools,
            Key.didOnboard: false,
            Key.alwaysVisible: false,
        ])
        port = defaults.integer(forKey: Key.port)
        approvalDelay = defaults.double(forKey: Key.approvalDelay)
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        autoExpand = defaults.bool(forKey: Key.autoExpand)
        dockBadgeEnabled = defaults.bool(forKey: Key.dockBadgeEnabled)
        autoApprovedToolsText = defaults.string(forKey: Key.autoApprovedTools) ?? Self.defaultAutoApprovedTools
        didCompleteOnboarding = defaults.bool(forKey: Key.didOnboard)
        alwaysVisible = defaults.bool(forKey: Key.alwaysVisible)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var autoApprovedTools: Set<String> {
        Set(autoApprovedToolsText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    var stateMachineConfig: StateMachineConfig {
        StateMachineConfig(approvalDelay: max(0.5, approvalDelay), autoApprovedTools: autoApprovedTools)
    }

    var validPort: UInt16 {
        (1024...65535).contains(port) ? UInt16(port) : UInt16(Self.defaultPort)
    }
}
