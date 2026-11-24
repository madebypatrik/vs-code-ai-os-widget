import AgentPillCore
import AppKit
import SwiftUI

/// `AgentPill --render-previews <dir>`: renders pill and card states to PNG (design check without a screen).
@MainActor
enum PreviewRenderer {
    static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "agentpill.preview")!
        let settings = AppSettings(defaults: defaults)

        func store(_ events: [(String, String, String?, String?)], ago: TimeInterval = 42) -> SessionStore {
            let store = SessionStore(settings: settings)
            for (name, session, tool, command) in events {
                store.ingest(HookEvent(
                    eventName: name, sessionId: session, cwd: "/Users/dev/projects/\(session)", toolName: tool,
                    toolInput: command.map { .object(["command": .string($0)]) }
                ))
            }
            store.debugAdvance(by: ago)
            return store
        }

        let approval = store([("UserPromptSubmit", "my-app", nil, nil),
                              ("PreToolUse", "my-app", "run_in_terminal", "npm run build")])
        let yourTurn = store([("Stop", "my-app", nil, nil)], ago: 75)
        let replied = store([("UserPromptSubmit", "my-app", nil, nil), ("Stop", "my-app", nil, nil)], ago: 2)
        let interim = store([("UserPromptSubmit", "my-app", nil, nil), ("Stop", "my-app", nil, nil),
                             ("PostToolUse", "my-app", "read_file", nil)], ago: 2)
        let working = store([("UserPromptSubmit", "my-app", nil, nil)], ago: 12)
        let multi = store([("UserPromptSubmit", "my-app", nil, nil),
                           ("PreToolUse", "my-app", "run_in_terminal", "npm run build"),
                           ("Stop", "web-app", nil, nil),
                           ("UserPromptSubmit", "api-server", nil, nil)])
        let idle = SessionStore(settings: settings)

        let panel = PanelModel()
        panel.isVisible = true
        for (name, s) in [("approval", approval), ("yourturn", yourTurn), ("replied", replied), ("interim", interim), ("working", working), ("multi", multi), ("idle", idle)] {
            write(PillView(store: s).padding(6).background(Color(white: 0.92)), to: dir.appendingPathComponent("pill-\(name).png"))
            let card = ActivityCardView(store: s, panel: panel, port: 47823, onOpen: { _ in }, onSnooze: {})
                .padding(10).background(Color(white: 0.92)).environment(\.colorScheme, .dark)
            write(card, to: dir.appendingPathComponent("card-\(name).png"))
            let widget = CompactWidgetView(store: s, onOpen: { _ in }, onSnooze: {}, onExpand: {})
                .padding(10).background(Color(white: 0.92)).environment(\.colorScheme, .dark)
            write(widget, to: dir.appendingPathComponent("widget-\(name).png"))
        }
        print("Previews written to \(dir.path)")
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
