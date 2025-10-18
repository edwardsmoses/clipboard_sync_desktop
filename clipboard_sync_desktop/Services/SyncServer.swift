import Combine
import Foundation
import Network

struct SyncClientInfo: Identifiable {
    let id: UUID
    let connection: NWConnection
    var deviceName: String?
}

@MainActor
final class SyncServer: ObservableObject {
    enum ServerState {
        case stopped
        case starting
        case listening(port: UInt16)
        case failed(Error)
    }

    @Published private(set) var state: ServerState = .stopped
    @Published private(set) var clients: [SyncClientInfo] = []

    private var listener: NWListener?
    private var queue = DispatchQueue(label: "com.clipboard.sync.server")
    private var cancellables: [UUID: NWConnection] = [:]
    private var isDiscoverable = true
    private let serviceName = "Clipboard Sync"

    func start(on port: UInt16 = 0, discoverable: Bool = true) {
        guard listener == nil else { return }
        state = .starting
        isDiscoverable = discoverable

        do {
            let parameters = NWParameters.tcp
            let websocketOptions = NWProtocolWebSocket.Options()
            websocketOptions.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(websocketOptions, at: 0)

            let nwPort = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: port)!
            let listener = try NWListener(using: parameters, on: nwPort)
            if discoverable {
                listener.service = NWListener.Service(name: serviceName, type: "_clipboardsync._tcp")
            } else {
                listener.service = nil
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection)
                }
            }

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue {
                            self.state = .listening(port: port)
                        }
                    case .failed(let error):
                        self.state = .failed(error)
                        self.stop()
                    default:
                        break
                    }
                }
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            state = .failed(error)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in cancellables.values {
            connection.cancel()
        }
        cancellables.removeAll()
        clients.removeAll()
        state = .stopped
        isDiscoverable = true
    }

    func broadcast(json: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        for client in cancellables.values {
            send(data: data, to: client)
        }
    }

    func updateDiscoverability(_ newValue: Bool) {
        guard isDiscoverable != newValue else { return }
        isDiscoverable = newValue
        if let listener {
            listener.service = newValue ? NWListener.Service(name: serviceName, type: "_clipboardsync._tcp") : nil
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let id = UUID()
        let client = SyncClientInfo(id: id, connection: connection, deviceName: nil)
        clients.append(client)
        cancellables[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.receive(on: connection, clientId: id)
                case .failed, .cancelled:
                    self.removeClient(id: id)
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, clientId: UUID) {
        connection.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    print("[server] receive error: \(error)")
                    self.removeClient(id: clientId)
                    return
                }

                if let data {
                    self.handleMessage(data, clientId: clientId)
                }

                self.receive(on: connection, clientId: clientId)
            }
        }
    }

    private func handleMessage(_ data: Data, clientId: UUID) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[server] invalid json")
            return
        }

        if let type = json["type"] as? String, type == "handshake" {
            let deviceName = json["payload"] as? [String: Any]
            if let name = deviceName?["deviceName"] as? String, let index = clients.firstIndex(where: { $0.id == clientId }) {
                clients[index].deviceName = name
            }
        }

        // Additional routing will be added when Android client is ready to communicate.
    }

    private func send(data: Data, to connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("[server] send error: \(error)")
            }
        })
    }

    private func removeClient(id: UUID) {
        cancellables[id]?.cancel()
        cancellables.removeValue(forKey: id)
        clients.removeAll { $0.id == id }
    }
}
