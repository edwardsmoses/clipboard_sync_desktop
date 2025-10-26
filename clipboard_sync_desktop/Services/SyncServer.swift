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
    // Notify the app of incoming clipboard events from clients
    var onClipboardEvent: (([String: Any]) -> Void)?

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
                        // Preserve failure state so the UI can surface it.
                        self.state = .failed(error)
                        self.cleanupConnections()
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
        cleanupConnections()
        state = .stopped
        isDiscoverable = true
    }

    private func cleanupConnections() {
        listener?.cancel()
        listener = nil
        for connection in cancellables.values {
            connection.cancel()
        }
        cancellables.removeAll()
        clients.removeAll()
    }

    func broadcast(json: Any, excluding excludedId: UUID? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        for (id, client) in cancellables {
            if let excluded = excludedId, id == excluded { continue }
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

        guard let type = json["type"] as? String else { return }
        switch type {
        case "handshake":
            let payload = json["payload"] as? [String: Any]
            if let name = payload?["deviceName"] as? String, let index = clients.firstIndex(where: { $0.id == clientId }) {
                clients[index].deviceName = name
            }
            // Reply to this client with server info so it can show a friendly name
            let serverName = Host.current().localizedName ?? "Mac"
            let ack: [String: Any] = [
                "type": "ack",
                "timestamp": Date().timeIntervalSince1970 * 1000,
                "payload": [
                    "serverName": serverName,
                    "clients": clients.map { [
                        "id": $0.id.uuidString,
                        "deviceName": $0.deviceName ?? "Unnamed device",
                    ] },
                ],
            ]
            send(json: ack, to: clientId)
        case "clipboard-event":
            // Re-broadcast the event to other clients
            broadcast(json: json, excluding: clientId)
            if let payload = json["payload"] as? [String: Any] {
                onClipboardEvent?(payload)
            }
        default:
            break
        }
    }

    private func send(json: Any, to clientId: UUID) {
        guard let connection = cancellables[clientId],
              let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        send(data: data, to: connection)
    }

    private func send(data: Data, to connection: NWConnection) {
        // Ensure WebSocket frames are sent as text, not binary.
        let wsMetadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [wsMetadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
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
