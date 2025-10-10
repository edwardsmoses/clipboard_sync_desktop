import Foundation

enum ClipboardContentType: String, Codable, CaseIterable {
    case text
    case html
    case image
    case file
    case unknown
}

enum ClipboardSyncState: String, Codable {
    case pending
    case synced
    case failed
}

enum ClipboardOrigin: String, Codable {
    case local
    case remote
}

struct ClipboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var contentType: ClipboardContentType
    var text: String?
    var html: String?
    var imageData: Data?
    var fileURL: URL?
    var createdAt: Date
    var updatedAt: Date
    var deviceId: String
    var deviceName: String
    var origin: ClipboardOrigin
    var isPinned: Bool
    var syncState: ClipboardSyncState
    var syncedAt: Date?
    var metadata: [String: String]?

    init(
        id: UUID = UUID(),
        contentType: ClipboardContentType,
        text: String? = nil,
        html: String? = nil,
        imageData: Data? = nil,
        fileURL: URL? = nil,
        createdAt: Date = .init(),
        updatedAt: Date = .init(),
        deviceId: String,
        deviceName: String,
        origin: ClipboardOrigin,
        isPinned: Bool = false,
        syncState: ClipboardSyncState = .pending,
        syncedAt: Date? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.text = text
        self.html = html
        self.imageData = imageData
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.origin = origin
        self.isPinned = isPinned
        self.syncState = syncState
        self.syncedAt = syncedAt
        self.metadata = metadata
    }

    var preview: String {
        switch contentType {
        case .text:
            return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .html:
            return html?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "<html>"
        case .image:
            let width = metadata?["width"] ?? "?"
            let height = metadata?["height"] ?? "?"
            return "Image (\(width)×\(height))"
        case .file:
            return fileURL?.lastPathComponent ?? "File"
        case .unknown:
            return "Unknown content"
        }
    }
}
