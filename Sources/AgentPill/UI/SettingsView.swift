import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let runningPort: UInt16
    let serverStatus: () -> String
    let installHooks: () -> String?
    let uninstallHooks: () -> String?

    @State private var hooksInstalled = HookInstaller().isInstalled
    @State private var installedPort = HookInstaller().installedPort
    @State private var message: String?
    @State private var accessibilityGranted = DockBadgeWatcher.isTrusted

    var body: some View {
        Form {
            Section("Beteende") {
                Toggle("Visa flytande widget under pillen hela tiden", isOn: $settings.alwaysVisible)
                Toggle("Fäll ut kortet automatiskt", isOn: $settings.autoExpand)
                    .disabled(settings.alwaysVisible)
                Toggle("Spela ljud vid godkännande", isOn: $settings.soundEnabled)
                Toggle("Starta vid inloggning", isOn: $settings.launchAtLogin)
                LabeledContent("Godkännande-fördröjning") {
                    HStack {
                        Slider(value: $settings.approvalDelay, in: 1...15, step: 0.5)
                        Text("\(settings.approvalDelay, specifier: "%.1f") s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-godkända verktyg (startar aldrig timern)")
                    TextField("read_file, list_dir, …", text: $settings.autoApprovedToolsText, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 12, design: .monospaced))
                }
            }

            Section("Dock-badge") {
                Toggle("Använd VS Codes Dock-badge som signal", isOn: $settings.dockBadgeEnabled)
                LabeledContent("Accessibility") {
                    HStack {
                        Text(accessibilityGranted ? "Beviljad" : "Saknas")
                            .foregroundStyle(accessibilityGranted ? Theme.green : .secondary)
                        if !accessibilityGranted {
                            Button("Begär") { DockBadgeWatcher.requestAccess() }
                        }
                    }
                }
            }

            Section("Server och hooks") {
                LabeledContent("Server", value: serverStatus())
                LabeledContent("Port") {
                    TextField("", value: $settings.port, format: .number.grouping(.never))
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                if settings.port != Int(runningPort) {
                    Text("Ny port används efter omstart. Installera om hooks så att report.sh pekar rätt.")
                        .font(.caption).foregroundStyle(Theme.orange)
                }
                LabeledContent("Hooks") {
                    HStack {
                        Text(hookStatus).foregroundStyle(.secondary)
                        Button(hooksInstalled ? "Installera om" : "Installera") {
                            message = installHooks()
                            refresh()
                        }
                        if hooksInstalled {
                            Button("Avinstallera") {
                                message = uninstallHooks()
                                refresh()
                            }
                        }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refresh)
    }

    private var hookStatus: String {
        guard hooksInstalled else { return "Ej installerade" }
        if let installedPort { return "Installerade (port \(installedPort))" }
        return "Installerade"
    }

    private func refresh() {
        let installer = HookInstaller()
        hooksInstalled = installer.isInstalled
        installedPort = installer.installedPort
        accessibilityGranted = DockBadgeWatcher.isTrusted
    }
}
