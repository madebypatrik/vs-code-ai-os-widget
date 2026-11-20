import AgentPillCore
import Foundation
import Network

/// Local HTTP server: `POST /event` on 127.0.0.1 only. `GET /health` answers "ok".
@MainActor
final class EventServer {
    enum Status: Equatable {
        case stopped, starting, listening, failed(String)
    }

    let port: UInt16
    var onEvent: ((HookEvent) -> Void)?
    var stateProvider: (() -> String)?
    var onStatusChange: ((Status) -> Void)?
    private(set) var status: Status = .stopped {
        didSet { onStatusChange?(status) }
    }

    private var listener: NWListener?
    private var buffers: [ObjectIdentifier: Data] = [:]

    init(port: UInt16) {
        self.port = port
    }

    func start() {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        // Bind to loopback only – never exposed on the network.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerStateChanged(state) }
            }
            status = .starting
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        status = .stopped
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready: status = .listening
        case .failed(let error):
            status = .failed(error.localizedDescription)
            listener?.cancel()
            listener = nil
        case .cancelled: if case .failed = status {} else { status = .stopped }
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        buffers[id] = Data()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                MainActor.assumeIsolated { _ = self?.buffers.removeValue(forKey: id) }
            default: break
            }
        }
        connection.start(queue: .main)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                let id = ObjectIdentifier(connection)
                if let data { self.buffers[id, default: Data()].append(data) }

                switch HTTPRequestParser.parse(self.buffers[id] ?? Data()) {
                case .complete(let request):
                    self.respond(to: request, on: connection)
                case .invalid(let reason):
                    self.send(HTTPRequestParser.response(status: 400, reason: "Bad Request", body: reason), on: connection)
                case .incomplete:
                    if isComplete || error != nil {
                        connection.cancel()
                    } else {
                        self.receive(on: connection)
                    }
                }
            }
        }
    }

    private func respond(to request: HTTPRequestParser.Request, on connection: NWConnection) {
        // Browsers always send Origin on cross-site requests; curl does not. Reject to block CSRF-style spoofing.
        if request.headers["origin"] != nil {
            send(HTTPRequestParser.response(status: 403, reason: "Forbidden"), on: connection)
            return
        }
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        switch (request.method, path) {
        case ("POST", "/event"):
            do {
                let event = try HookEvent.decode(request.body)
                send(HTTPRequestParser.response(status: 200, reason: "OK", body: "ok"), on: connection)
                onEvent?(event)
            } catch {
                send(HTTPRequestParser.response(status: 422, reason: "Unprocessable Entity", body: "invalid payload"), on: connection)
            }
        case ("GET", "/state"):
            send(HTTPRequestParser.response(status: 200, reason: "OK", body: stateProvider?() ?? "{}"), on: connection)
        case ("GET", "/health"):
            send(HTTPRequestParser.response(status: 200, reason: "OK", body: "ok"), on: connection)
        default:
            send(HTTPRequestParser.response(status: 404, reason: "Not Found"), on: connection)
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
