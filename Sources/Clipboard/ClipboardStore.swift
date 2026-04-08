import AppKit
import Combine
import Foundation
import ImageIO

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let copiedAt: Date
    /// Plain text clip; nil when the clip is image-only.
    var text: String?
    /// PNG bytes for an image clip; nil when the clip is text-only.
    var imagePNGData: Data?

    init(id: UUID = UUID(), copiedAt: Date = Date(), text: String?, imagePNGData: Data?) {
        self.id = id
        self.copiedAt = copiedAt
        self.text = text
        self.imagePNGData = imagePNGData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        copiedAt = try c.decode(Date.self, forKey: .copiedAt)
        if let t = try c.decodeIfPresent(String.self, forKey: .text) {
            text = t.isEmpty ? nil : t
        } else {
            text = nil
        }
        imagePNGData = try c.decodeIfPresent(Data.self, forKey: .imagePNGData)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(copiedAt, forKey: .copiedAt)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(imagePNGData, forKey: .imagePNGData)
    }

    private enum CodingKeys: String, CodingKey {
        case id, copiedAt, text, imagePNGData
    }

    var isImage: Bool { imagePNGData != nil }

    /// One-line preview for the list (not used for paste).
    var previewText: String {
        if isImage {
            guard let d = imagePNGData,
                  let src = CGImageSourceCreateWithData(d as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? NSNumber,
                  let h = props[kCGImagePropertyPixelHeight] as? NSNumber
            else { return "Image" }
            return "Image · \(w.intValue) × \(h.intValue)"
        }
        return text ?? ""
    }
}

private extension NSImage {
    /// Raster PNG for storage and paste. Handles file-backed / lazy images that would otherwise show as icons in SwiftUI.
    func pngDataForClipboard() -> Data? {
        for rep in representations {
            if let bmp = rep as? NSBitmapImageRep,
               let png = bmp.representation(using: .png, properties: [:]),
               !png.isEmpty {
                return png
            }
        }
        return rasterizeToPNG()
    }

    private func rasterizeToPNG() -> Data? {
        let logicalSize = size
        guard logicalSize.width > 0, logicalSize.height > 0 else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pw = max(1, Int(ceil(logicalSize.width * scale)))
        let ph = max(1, Int(ceil(logicalSize.height * scale)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pw,
            pixelsHigh: ph,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = logicalSize
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        let dst = NSRect(x: 0, y: 0, width: CGFloat(pw), height: CGFloat(ph))
        let src = NSRect(x: 0, y: 0, width: logicalSize.width, height: logicalSize.height)
        draw(in: dst, from: src, operation: .copy, fraction: 1.0, respectFlipped: false, hints: nil)
        return rep.representation(using: .png, properties: [:])
    }
}

/// Decodes stored PNG bytes to a bitmap CGImage (avoids AppKit file-icon style NSImage in SwiftUI).
func cgImageFromClipboardPNGData(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Keeps clipboard history in copy order (newest at index 0). Persists across app restarts.
@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    private static let maxItems = 200
    private static let pollInterval: TimeInterval = 0.35

    @Published private(set) var items: [ClipboardItem] = []

    private var lastChangeCount: Int
    private var timer: Timer?
    private var saveDebounce: Timer?

    private var persistenceURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        load()
    }

    func startMonitoring() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPasteboard() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if let image = readImage(from: pb), let png = image.pngDataForClipboard() {
            if let first = items.first, first.imagePNGData == png { return }
            let entry = ClipboardItem(text: nil, imagePNGData: png)
            items.insert(entry, at: 0)
            trimAndSave()
            return
        }

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        if let first = items.first, first.text == text, !first.isImage { return }

        let entry = ClipboardItem(text: text, imagePNGData: nil)
        items.insert(entry, at: 0)
        trimAndSave()
    }

    /// Reads a raster image from the pasteboard when one is offered (prefers real image data over a lone filename string).
    private func readImage(from pb: NSPasteboard) -> NSImage? {
        if pb.canReadObject(forClasses: [NSImage.self], options: nil),
           let objects = pb.readObjects(forClasses: [NSImage.self], options: nil),
           let img = objects.compactMap({ $0 as? NSImage }).first {
            return img
        }
        if let tiff = pb.data(forType: .tiff), let img = NSImage(data: tiff) {
            return img
        }
        if let png = pb.data(forType: .png), let img = NSImage(data: png) {
            return img
        }
        // Finder and others: copied file(s) as URL — load bitmap if it’s an image file.
        if pb.canReadObject(forClasses: [NSURL.self], options: nil),
           let objects = pb.readObjects(forClasses: [NSURL.self], options: nil) {
            for obj in objects {
                guard let url = obj as? URL, url.isFileURL else { continue }
                if let img = NSImage(contentsOf: url), img.pngDataForClipboard() != nil {
                    return img
                }
            }
        }
        return nil
    }

    private func trimAndSave() {
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        scheduleSave()
    }

    /// Places the clip on the pasteboard for picking from history or pasting into another app.
    func copyItemToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = item.imagePNGData, !png.isEmpty {
            pb.setData(png, forType: .png)
            if let rep = NSBitmapImageRep(data: png),
               let tiff = rep.representation(using: .tiff, properties: [:]),
               !tiff.isEmpty {
                pb.setData(tiff, forType: .tiff)
            }
        } else if let text = item.text {
            pb.setString(text, forType: .string)
        }
        lastChangeCount = pb.changeCount
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        scheduleSave()
    }

    func clearAll() {
        items.removeAll()
        scheduleSave()
    }

    private func scheduleSave() {
        saveDebounce?.invalidate()
        saveDebounce = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.saveNow() }
        }
    }

    private func saveNow() {
        saveDebounce?.invalidate()
        saveDebounce = nil
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {}
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            items = []
        }
    }
}
