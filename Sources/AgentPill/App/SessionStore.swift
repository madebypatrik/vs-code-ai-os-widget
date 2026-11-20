import AgentPillCore
import Foundation
import Observation

/// Observable wrapper around `StateMachine` that drives timers and publishes transitions.
@MainActor
@Observable
final class SessionStore {
    private(set) var machine: StateMachine
    /// Updated every second so elapsed-time labels refresh.
    private(set) var now = Date()

    @ObservationIgnored var onTransitions: (([StateTransition]) -> Void)?
    @ObservationIgnored var onTick: ((Date) -> Void)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var timer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
        machine = StateMachine(config: settings.stateMachineConfig)
    }

    var sessions: [Session] { machine.orderedSessions }
    var attentionSessions: [Session] { machine.attentionSessions }
    var aggregateState: AgentState { machine.aggregateState }

    func start() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common) // keep ticking while menus are open
        self.timer = timer
    }

    func ingest(_ event: HookEvent) {
        syncConfig()
        now = Date()
        publish(machine.handle(event, now: now))
    }

    func dockBadgeAppeared() {
        now = Date()
        publish(machine.dockBadgeAppeared(now: now))
    }

    func remove(_ sessionId: String) {
        if let transition = machine.remove(sessionId: sessionId) { publish([transition]) }
    }

    /// Previews/debug: pretend `seconds` have passed (runs timers).
    func debugAdvance(by seconds: TimeInterval) {
        now = Date().addingTimeInterval(seconds)
        publish(machine.tick(now: now))
    }

    /// JSON snapshot for `GET /state` (debugging, local only). Tool details are omitted.
    func stateJSON() -> String {
        let sessions = machine.orderedSessions.map { s -> [String: Any] in
            ["id": s.id, "project": s.projectName, "state": "\(s.state)",
             "tool": s.pendingTool?.name ?? NSNull(), "since": Int(now.timeIntervalSince(s.stateSince))]
        }
        let object: [String: Any] = ["aggregate": "\(machine.aggregateState.displayState)", "sessions": sessions]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func tick() {
        syncConfig()
        now = Date()
        publish(machine.tick(now: now))
        onTick?(now)
    }

    private func syncConfig() {
        let config = settings.stateMachineConfig
        if machine.config != config { machine.config = config }
    }

    private func publish(_ transitions: [StateTransition]) {
        guard !transitions.isEmpty else { return }
        onTransitions?(transitions)
    }
}
