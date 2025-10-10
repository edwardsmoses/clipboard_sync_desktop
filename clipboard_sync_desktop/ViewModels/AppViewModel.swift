import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var historyStore = ClipboardHistoryStore()
    @Published private(set) var syncServer = SyncServer()
    @Published var isWatching = false

    private let watcher = PasteboardWatcher()
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

        historyStore.load()

        watcher.onSnapshot = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                await self?.ingest(snapshot: snapshot)
            }
        }
    }

    func start() {
        guard !isWatching else { return }
        watcher.start()
        syncServer.start()
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

    func togglePin(entry: ClipboardEntry) {
        var updated = entry
        updated.isPinned.toggle()
        historyStore.upsert(updated)
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

        if let text = entry.text {
            entryPayload["text"] = text
        }

        if let html = entry.html {
            entryPayload["html"] = html
        }

        if let imageData = entry.imageData {
            let base64 = imageData.base64EncodedString()
            entryPayload["imageUri"] = "data:image/png;base64,\(base64)"
        }

        if let syncedAt = entry.syncedAt {
            entryPayload["syncedAt"] = syncedAt.timeIntervalSince1970 * 1000
        }

        if let metadata = entry.metadata {
            entryPayload["metadata"] = metadata
        }

        let envelope: [String: Any] = [
            "type": "clipboard-event",
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "payload": entryPayload,
        ]

        syncServer.broadcast(json: envelope)
    }
}
