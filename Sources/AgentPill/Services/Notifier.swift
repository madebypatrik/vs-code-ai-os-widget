import AgentPillCore
import AppKit
@preconcurrency import UserNotifications

/// macOS notifications + sound. Clicking a notification opens VS Code at the session's cwd.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((String?) -> Void)?

    /// UNUserNotificationCenter crashes outside an .app bundle (e.g. `swift run`).
    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil

    override init() {
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard let center else { return .denied }
        return await center.notificationSettings().authorizationStatus
    }

    func notify(_ session: Session, playSound: Bool) {
        if playSound { NSSound(named: "Glass")?.play() }
        guard let center else { return }

        let content = UNMutableNotificationContent()
        switch session.state {
        case .needsApproval:
            content.title = "Väntar på godkännande"
            content.body = session.pendingTool?.plainText ?? "Copilot behöver ditt godkännande"
        case .yourTurn:
            content.title = "Din tur"
            content.body = "Copilot är klar och väntar på dig"
        default:
            return
        }
        content.subtitle = session.projectName
        content.userInfo = ["cwd": session.cwd]
        content.threadIdentifier = session.id

        let request = UNNotificationRequest(identifier: "\(session.id)-\(session.state.rawValue)", content: content, trigger: nil)
        center.add(request)
    }

    func removeDelivered(for sessionId: String) {
        center?.removeDeliveredNotifications(withIdentifiers: AgentState.allCases.map { "\(sessionId)-\($0.rawValue)" })
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let cwd = response.notification.request.content.userInfo["cwd"] as? String
        await MainActor.run { onOpen?(cwd) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
