import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var historyStore = ClipboardHistoryStore()
    @Published private(set) var syncServer = SyncServer()
    @Published private(set) var networkSummary: NetworkSummary = .disconnected
    @Published var isWatching = false
    @Published var isDiscoverable: Bool

    private let watcher = PasteboardWatcher()
    private let networkMonitor = NetworkMonitor()
    private var cancellables = Set<AnyCancellable>()
    private let deviceId: String
    private let deviceName: String

    init() {
        let defaults = UserDefaults.standard
        if let storedId = defaults.string(forKey: "device.identifier") {
            deviceId = storedId
        } else {
            let newId = UUID().uuidString
            defaults.set(newId, forKey: "device.identifier")
            deviceId = newId
        }
        deviceName = Host.current().localizedName ?? "Mac"

        if defaults.object(forKey: "settings.discoverable") == nil {
            defaults.set(true, forKey: "settings.discoverable")
        }
        isDiscoverable = defaults.bool(forKey: "settings.discoverable")

        historyStore.load()

        watcher.onSnapshot = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                await self?.ingest(snapshot: snapshot)
            }
        }

        networkMonitor.$summary
            .receive(on: RunLoop.main)
            .sink { [weak self] summary in
                self?.networkSummary = summary
            }
            .store(in: &cancellables)
        networkMonitor.start()
    }

    deinit {
        networkMonitor.stop()
    }

    func start() {
        guard !isWatching else { return }
        watcher.start()
        // Use a stable port so previously saved endpoints remain valid.
        syncServer.start(on: 51858, discoverable: isDiscoverable)
        syncServer.onClipboardEvent = { [weak self] payload in
            Task { @MainActor [weak self] in
                self?.ingestRemoteClipboardEvent(payload: payload)
            }
        }
        isWatching = true
    }

    func stop() {
        watcher.stop()
        syncServer.stop()
        isWatching = false
    }

    func delete(entry: ClipboardEntry) {
        historyStore.remove(id: entry.id)
    }

    func deleteAll() {
        historyStore.clear()
    }

    func togglePin(entry: ClipboardEntry) {
        var updated = entry
        updated.isPinned.toggle()
        historyStore.upsert(updated)
    }

    func setDiscoverable(_ newValue: Bool) {
        guard isDiscoverable != newValue else { return }
        isDiscoverable = newValue
        UserDefaults.standard.set(newValue, forKey: "settings.discoverable")
        syncServer.updateDiscoverability(newValue)
    }

    var pairingEndpoint: String? {
        guard case let .listening(port) = syncServer.state else { return nil }
        if let address = networkSummary.localAddress {
            return "ws://\(address):\(port)"
        }
        let host = ProcessInfo.processInfo.hostName
        return "ws://\(host):\(port)"
    }

    var pairingCode: String? {
        guard case let .listening(port) = syncServer.state,
              let address = networkSummary.localAddress else {
            return nil
        }
        return PairingCode.generate(address: address, port: port)
    }

    private func ingest(snapshot: PasteboardSnapshot) async {
        let now = Date()
        let entry = ClipboardEntry(
            contentType: snapshot.contentType,
            text: snapshot.text,
            html: snapshot.html,
            imageData: snapshot.imageData,
            fileURL: nil,
            createdAt: now,
            updatedAt: now,
            deviceId: deviceId,
            deviceName: deviceName,
            origin: .local,
            isPinned: false,
            syncState: .pending,
            syncedAt: nil,
            metadata: snapshot.metadata
        )

        historyStore.append(entry)
        broadcast(entry: entry)
    }

    private func broadcast(entry: ClipboardEntry) {
        var entryPayload: [String: Any] = [
            "id": entry.id.uuidString,
            "contentType": entry.contentType.rawValue,
            "createdAt": entry.createdAt.timeIntervalSince1970 * 1000,
            "updatedAt": entry.updatedAt.timeIntervalSince1970 * 1000,
            "deviceId": entry.deviceId,
            "deviceName": entry.deviceName,
            "origin": entry.origin.rawValue,
            "isPinned": entry.isPinned,
            "syncState": entry.syncState.rawValue,
        ]

        if let text = entry.text { entryPayload["text"] = text }
        if let html = entry.html { entryPayload["html"] = html }
        if let imageData = entry.imageData {
            let base64 = imageData.base64EncodedString()
            entryPayload["imageUri"] = "data:image/png;base64,\(base64)"
        }
        if let syncedAt = entry.syncedAt { entryPayload["syncedAt"] = syncedAt.timeIntervalSince1970 * 1000 }
        if let metadata = entry.metadata { entryPayload["metadata"] = metadata }

        let event: [String: Any] = [
            "id": entry.id.uuidString,
            "eventType": "added",
            "payload": entryPayload,
        ]

        let envelope: [String: Any] = [
            "type": "clipboard-event",
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "payload": event,
        ]

        syncServer.broadcast(json: envelope)
    }

    private func ingestRemoteClipboardEvent(payload: [String: Any]) {
        guard let eventType = payload["eventType"] as? String, eventType == "added",
              let entryDict = payload["payload"] as? [String: Any] else {
            return
        }

        // Map JSON to ClipboardEntry
        let id = (entryDict["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let contentType = ClipboardContentType(rawValue: (entryDict["contentType"] as? String) ?? "text") ?? .text
        let text = entryDict["text"] as? String
        let html = entryDict["html"] as? String
        var imageData: Data? = nil
        if let imageUri = entryDict["imageUri"] as? String, let range = imageUri.range(of: ",") {
            let base64 = String(imageUri[range.upperBound...])
            imageData = Data(base64Encoded: base64)
        }
        let createdAtMs = (entryDict["createdAt"] as? Double) ?? (entryDict["createdAt"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
        let updatedAtMs = (entryDict["updatedAt"] as? Double) ?? (entryDict["updatedAt"] as? NSNumber)?.doubleValue ?? createdAtMs
        let createdAt = Date(timeIntervalSince1970: createdAtMs / 1000)
        let updatedAt = Date(timeIntervalSince1970: updatedAtMs / 1000)
        let deviceId = (entryDict["deviceId"] as? String) ?? "remote"
        let deviceName = (entryDict["deviceName"] as? String) ?? "Remote device"
        let isPinned = (entryDict["isPinned"] as? Bool) ?? false
        let syncState = ClipboardSyncState(rawValue: (entryDict["syncState"] as? String) ?? "pending") ?? .pending
        var syncedAt: Date? = nil
        if let syncedAtMs = (entryDict["syncedAt"] as? Double) ?? (entryDict["syncedAt"] as? NSNumber)?.doubleValue {
            syncedAt = Date(timeIntervalSince1970: syncedAtMs / 1000)
        }
        var metadata: [String: String]? = nil
        if let md = entryDict["metadata"] as? [String: Any] {
            var mapped: [String: String] = [:]
            for (k, v) in md { mapped[k] = String(describing: v) }
            metadata = mapped
        }

        let entry = ClipboardEntry(
            id: id,
            contentType: contentType,
            text: text,
            html: html,
            imageData: imageData,
            fileURL: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deviceId: deviceId,
            deviceName: deviceName,
            origin: .remote,
            isPinned: isPinned,
            syncState: syncState,
            syncedAt: syncedAt,
            metadata: metadata
        )

        historyStore.upsert(entry)
    }
}
