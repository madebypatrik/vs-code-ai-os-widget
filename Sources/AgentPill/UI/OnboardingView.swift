import AppKit
import SwiftUI

/// First-run flow: install hooks, enable VS Code settings, grant Accessibility, notifications.
struct OnboardingView: View {
    let settings: AppSettings
    let installHooks: () -> String?   // returns an error message, or nil on success
    let requestNotifications: () async -> Bool
    let onDone: () -> Void

    @State private var hooksInstalled = HookInstaller().isInstalled
    @State private var hookError: String?
    @State private var copied = false
    @State private var accessibilityGranted = DockBadgeWatcher.isTrusted
    @State private var notificationsGranted: Bool?

    static let vscodeSettingsJSON = """
    {
      "chat.notifyWindowOnConfirmation": "always",
      "chat.notifyWindowOnResponseReceived": "always"
    }
    """

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Circle().fill(Theme.orange).frame(width: 10, height: 10)
                Text("Välkommen till AgentPill").font(.title2.weight(.semibold))
            }
            Text("AgentPill visar i menyraden när Copilot i VS Code väntar på dig. Tre steg:")
                .foregroundStyle(.secondary)

            step(1, "Installera hooks", done: hooksInstalled) {
                Text("Skapar `~/.agentpill/report.sh` och `~/.copilot/hooks/agentpill.json`. Befintliga filer sparas som `*.bak`.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(hooksInstalled ? "Installera om" : "Installera hooks") {
                        hookError = installHooks()
                        hooksInstalled = HookInstaller().isInstalled
                    }
                    if let hookError { Text(hookError).foregroundStyle(.red).font(.caption) }
                }
            }

            step(2, "Slå på i VS Code", done: false, optional: true) {
                Text("Lägg till i VS Codes `settings.json` (styr fönsternotiser och Dock-badge):")
                    .font(.callout).foregroundStyle(.secondary)
                Text(Self.vscodeSettingsJSON)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                Button(copied ? "Kopierat ✓" : "Kopiera JSON") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.vscodeSettingsJSON, forType: .string)
                    copied = true
                }
                Text("Kontrollera tillåtna värden i VS Code (t.ex. `off` / `windowNotFocused` / `always`).")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            step(3, "Ge Accessibility-behörighet", done: accessibilityGranted, optional: true) {
                Text("Behövs för att läsa VS Codes Dock-badge – en extra signal för ”väntar på godkännande”.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Begär behörighet") { DockBadgeWatcher.requestAccess() }
                    Button("Öppna Systeminställningar") { DockBadgeWatcher.openAccessibilitySettings() }
                }
            }

            Divider()

            HStack {
                Button(notificationButtonTitle) {
                    Task { notificationsGranted = await requestNotifications() }
                }
                Toggle("Starta vid inloggning", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                Spacer()
                Button("Klar") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onReceive(timer) { _ in accessibilityGranted = DockBadgeWatcher.isTrusted }
    }

    private var notificationButtonTitle: String {
        switch notificationsGranted {
        case .some(true): "Notiser på ✓"
        case .some(false): "Notiser nekade"
        case .none: "Tillåt notiser"
        }
    }

    @ViewBuilder
    private func step(_ number: Int, _ title: String, done: Bool, optional: Bool = false,
                      @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Theme.green : Color.primary.opacity(0.1)).frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .semibold))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if optional { Text("valfritt").font(.caption).foregroundStyle(.tertiary) }
                }
                content()
            }
        }
    }
}
