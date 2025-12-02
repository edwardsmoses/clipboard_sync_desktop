import Combine
import Foundation

struct SyncClientInfo: Identifiable, Equatable {
    let id: String
    var deviceName: String
}

private struct RelaySession: Decodable {
    let token: String
    let hostWebsocketUrl: URL
    let clientWebsocketUrl: URL
    let expiresIn: TimeInterval
}

@MainActor
final class SyncServer: ObservableObject {
    enum ServerState: Equatable {
        case stopped
        case connecting
        case connected(token: String)
        case failed(String)
    }

    @Published private(set) var state: ServerState = .stopped
    @Published private(set) var clients: [SyncClientInfo] = []

    var onClipboardEvent: (([String: Any]) -> Void)?

    private let deviceId: String
    private let deviceName: String

    private var session: RelaySession?
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private var reconnectTask: Task<Void, Never>?
    private var isDiscoverable = true
    private var shouldRun = false

    init(deviceId: String, deviceName: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 120
        configuration.timeoutIntervalForRequest = 120
        self.urlSession = URLSession(configuration: configuration)
    }

    @MainActor deinit {
        stop()
    }

    func start(discoverable: Bool) {
        guard !shouldRun else { return }
        shouldRun = true
        isDiscoverable = discoverable
        state = .connecting
        Task {
            await establishSession()
        }
    }

    func stop() {
        shouldRun = false
        reconnectTask?.cancel()
        reconnectTask = nil
        clients.removeAll()
        session = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        state = .stopped
    }

    func updateDiscoverability(_ newValue: Bool) {
        guard isDiscoverable != newValue else { return }
        isDiscoverable = newValue
        sendHandshake()
    }

    func broadcast(json: Any) {
        guard let socket = webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        socket.send(.string(text)) { [weak self] error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.handleSocketFailure(error)
                }
            }
        }
    }

    var clientEndpoint: URL? {
        session?.clientWebsocketUrl
    }

    var pairingCode: String? {
        guard case let .connected(token) = state else { return nil }
        return PairingCode.displayString(for: token)
    }

    private func establishSession() async {
        do {
            let session = try await createSession()
            guard shouldRun else { return }
            self.session = session
            state = .connected(token: session.token)
            connectWebSocket(at: session.hostWebsocketUrl)
        } catch {
            state = .failed(error.localizedDescription)
            scheduleReconnect()
        }
    }

    private func createSession() async throws -> RelaySession {
        var request = URLRequest(url: RelayConfiguration.apiBaseURL.appendingPathComponent("v1/sessions"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw RelayError.sessionCreationFailed("Relay rejected request: \(body)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RelaySession.self, from: data)
    }

    private func connectWebSocket(at url: URL) {
        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        listen()
        sendHandshake()
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                Task { @MainActor in
                    self.handleSocketFailure(error)
                }
            case .success(let message):
                Task { @MainActor in
                    self.handle(message)
                }
                self.listen()
            }
        }
    }

    private func sendHandshake() {
        guard session != nil else { return }
        let payload: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": deviceName,
            "discoverable": isDiscoverable
        ]
        let envelope: [String: Any] = [
            "type": "handshake",
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "payload": payload
        ]
        broadcast(json: envelope)
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handle(text: text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handle(text: text)
            }
        @unknown default:
            break
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "ack":
            if let payload = json["payload"] as? [String: Any],
               let rows = payload["clients"] as? [[String: Any]] {
                clients = rows.map { row in
                    let id = row["id"] as? String ?? UUID().uuidString
                    let name = row["deviceName"] as? String ?? "Device"
                    return SyncClientInfo(id: id, deviceName: name)
                }
            }
        case "clipboard-event":
            if let payload = json["payload"] as? [String: Any] {
                onClipboardEvent?(payload)
            }
        default:
            break
        }
    }

    private func handleSocketFailure(_ error: Error) {
        clients.removeAll()
        session = nil
        webSocketTask?.cancel()
        webSocketTask = nil

        guard shouldRun else {
            state = .stopped
            return
        }

        state = .failed(error.localizedDescription)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        guard shouldRun else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                self?.state = .connecting
            }
            await self?.establishSession()
        }
    }
}

enum RelayError: Error, LocalizedError {
    case sessionCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed(let reason):
            return reason
        }
    }
}
