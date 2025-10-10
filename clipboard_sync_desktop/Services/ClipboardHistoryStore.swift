import Combine
import Foundation

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "clipboard_history.json") {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "clipboard-sync"
        let directory = supportDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try decoder.decode([ClipboardEntry].self, from: data)
        } catch {
            print("[history] Failed to load history: \(error)")
            entries = []
        }
    }

    func save() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[history] Failed to persist history: \(error)")
        }
    }

    func append(_ entry: ClipboardEntry) {
        entries.insert(entry, at: 0)
        trim()
        save()
    }

    func upsert(_ entry: ClipboardEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        trim()
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func markSynced(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].syncState = .synced
        entries[index].syncedAt = Date()
        save()
    }

    private func trim(maxCount: Int = 500) {
        if entries.count > maxCount {
            entries = Array(entries.prefix(maxCount))
        }
    }
}
