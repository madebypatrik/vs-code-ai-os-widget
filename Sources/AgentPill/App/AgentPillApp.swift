import AppKit
import ServiceManagement

@main
@MainActor
enum AgentPillApp {
    static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-previews") {
            let dir = index + 1 < args.count ? args[index + 1] : "previews"
            PreviewRenderer.run(outputDirectory: dir)
            return
        }
        if args.contains("--install-hooks") || args.contains("--uninstall-hooks") {
            let installer = HookInstaller()
            do {
                if args.contains("--install-hooks") {
                    try installer.install(port: AppSettings().validPort)
                    print("Hooks installerade: \(installer.hooksURL.path)")
                } else {
                    try installer.uninstall()
                    print("Hooks avinstallerade")
                }
            } catch {
                print("Fel: \(error.localizedDescription)")
            }
            return
        }
        if args.contains("--register-login-item") || args.contains("--unregister-login-item") {
            LoginItemCLI.run(register: args.contains("--register-login-item"))
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // No Dock icon, also when run outside the bundle.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

/// `AgentPill --register-login-item` / `--unregister-login-item`: toggles "open at login" and exits.
@MainActor
enum LoginItemCLI {
    static func run(register: Bool) {
        let service = SMAppService.mainApp
        do {
            if register {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Fel: \(error.localizedDescription)")
        }
        switch service.status {
        case .enabled: print("Startar vid inloggning: på")
        case .requiresApproval: print("Kräver godkännande i Systeminställningar › Allmänt › Inloggningsobjekt")
        case .notRegistered: print("Startar vid inloggning: av")
        case .notFound: print("Hittades inte (kör från .app-paketet)")
        @unknown default: print("Okänd status")
        }
    }
}
