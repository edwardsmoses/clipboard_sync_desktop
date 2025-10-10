import AppKit
import Foundation

struct PasteboardSnapshot {
    let contentType: ClipboardContentType
    let text: String?
    let html: String?
    let imageData: Data?
    let metadata: [String: String]?
}

final class PasteboardWatcher {
    private let pasteboard: NSPasteboard
    private var changeCount: Int
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.clipboard.sync.pasteboard")

    var onSnapshot: ((PasteboardSnapshot) -> Void)?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.changeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval = 1.0) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { [weak self] _ in
            self?.poll()
        })
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard changeCount != pasteboard.changeCount else { return }
        changeCount = pasteboard.changeCount

        queue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.readPasteboard()
            DispatchQueue.main.async {
                if let snapshot {
                    self.onSnapshot?(snapshot)
                }
            }
        }
    }

    private func readPasteboard() -> PasteboardSnapshot? {
        if let string = pasteboard.string(forType: .string) {
            return PasteboardSnapshot(
                contentType: .text,
                text: string,
                html: nil,
                imageData: nil,
                metadata: nil
            )
        }

        if let data = pasteboard.data(forType: .rtf), let attributed = try? NSAttributedString(data: data, options: [:], documentAttributes: nil) {
            return PasteboardSnapshot(
                contentType: .html,
                text: attributed.string,
                html: attributed.string,
                imageData: nil,
                metadata: nil
            )
        }

        if let imageData = pasteboard.data(forType: .tiff), let image = NSImage(data: imageData) {
            let representations = image.representations
            let pixelWidth = representations.first?.pixelsWide ?? 0
            let pixelHeight = representations.first?.pixelsHigh ?? 0
            let pngData = NSBitmapImageRep(data: imageData)?.representation(using: .png, properties: [:])
            return PasteboardSnapshot(
                contentType: .image,
                text: nil,
                html: nil,
                imageData: pngData,
                metadata: [
                    "width": String(pixelWidth),
                    "height": String(pixelHeight)
                ]
            )
        }

        return nil
    }
}
