import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let copiedAt: Date
    /// Plain text clip; nil when the clip is image-only.
    var text: String?
    /// PNG bytes for an image clip; nil when the clip is text-only.
    var imagePNGData: Data?
    /// Original filename when the clip came from a file used for Finder-style names when pasting as a file.
    var sourceFilename: String?

    init(id: UUID = UUID(), copiedAt: Date = Date(), text: String?, imagePNGData: Data?, sourceFilename: String? = nil) {
        self.id = id
        self.copiedAt = copiedAt
        self.text = text
        self.imagePNGData = imagePNGData
        self.sourceFilename = sourceFilename
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
        sourceFilename = try c.decodeIfPresent(String.self, forKey: .sourceFilename)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(copiedAt, forKey: .copiedAt)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(imagePNGData, forKey: .imagePNGData)
        try c.encodeIfPresent(sourceFilename, forKey: .sourceFilename)
    }

    private enum CodingKeys: String, CodingKey {
        case id, copiedAt, text, imagePNGData, sourceFilename
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
    private static let filenamesPboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    private static var imagePasteScratchDir: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardImagePaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

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

        if let pair = readImageWithSource(from: pb), let png = pair.image.pngDataForClipboard() {
            if let first = items.first, first.imagePNGData == png { return }
            let entry = ClipboardItem(text: nil, imagePNGData: png, sourceFilename: pair.sourceFilename)
            items.insert(entry, at: 0)
            trimAndSave()
            return
        }

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        if let first = items.first, first.text == text, !first.isImage { return }

        let entry = ClipboardItem(text: text, imagePNGData: nil, sourceFilename: nil)
        items.insert(entry, at: 0)
        trimAndSave()
    }

    private struct ImagePasteboardPair {
        let image: NSImage
        let sourceFilename: String?
    }

    /// Reads a raster image from the pasteboard. File references are handled **before** `NSImage` so Finder’s generic file icon is not mistaken for the image.
    private func readImageWithSource(from pb: NSPasteboard) -> ImagePasteboardPair? {
        if let pair = readImageFromFilePasteboard(pb) {
            return ImagePasteboardPair(image: pair.image, sourceFilename: pair.sourceFilename)
        }
        if let tiff = pb.data(forType: .tiff), let img = NSImage(data: tiff) {
            return ImagePasteboardPair(image: img, sourceFilename: nil)
        }
        if let png = pb.data(forType: .png), let img = NSImage(data: png) {
            return ImagePasteboardPair(image: img, sourceFilename: nil)
        }
        if pb.canReadObject(forClasses: [NSImage.self], options: nil),
           let objects = pb.readObjects(forClasses: [NSImage.self], options: nil),
           let img = objects.compactMap({ $0 as? NSImage }).first {
            return ImagePasteboardPair(image: img, sourceFilename: nil)
        }
        return nil
    }

    /// Loads pixels from copied **file** URLs (Finder icon selection, etc.), not the preview icon on the pasteboard.
    private func readImageFromFilePasteboard(_ pb: NSPasteboard) -> (image: NSImage, sourceFilename: String)? {
        var urls: [URL] = []

        if pb.canReadObject(forClasses: [NSURL.self], options: nil),
           let objects = pb.readObjects(forClasses: [NSURL.self], options: nil) {
            for obj in objects {
                let url: URL?
                if let u = obj as? URL {
                    url = u
                } else if let n = obj as? NSURL {
                    url = n as URL
                } else {
                    url = nil
                }
                if let u = url, u.isFileURL {
                    urls.append(u.standardizedFileURL)
                }
            }
        }

        if let s = pb.string(forType: .fileURL),
           let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
           u.isFileURL {
            urls.append(u.standardizedFileURL)
        }

        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pb.propertyList(forType: filenamesType) as? [String] {
            for p in paths {
                urls.append(URL(fileURLWithPath: p).standardizedFileURL)
            }
        }

        for item in pb.pasteboardItems ?? [] {
            if let s = item.string(forType: .fileURL),
               let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
               u.isFileURL {
                urls.append(u.standardizedFileURL)
            }
        }

        var seen: Set<URL> = []
        for url in urls where seen.insert(url).inserted {
            if let img = Self.loadRasterFromImageFile(at: url) {
                return (image: img, sourceFilename: url.lastPathComponent)
            }
        }
        return nil
    }

    private static func loadRasterFromImageFile(at url: URL) -> NSImage? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }
        guard let data = try? Data(contentsOf: url), data.count > 32 else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let typeId = CGImageSourceGetType(source),
              let ut = UTType(typeId as String),
              ut.conforms(to: .image)
        else { return nil }
        return NSImage(data: data)
    }

    private func trimAndSave() {
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        scheduleSave()
    }

    private static func sanitizedImageStem(from sourceFilename: String?) -> String {
        guard let full = sourceFilename?.trimmingCharacters(in: .whitespacesAndNewlines), !full.isEmpty else {
            return "Clipboard Image"
        }
        var stem = (full as NSString).deletingPathExtension
        if stem.isEmpty { stem = full }
        for bad in ["/", ":", "\\", "?", "%", "*", "|", "\"", "<", ">", "\u{7f}"] {
            stem = stem.replacingOccurrences(of: bad, with: "_")
        }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Clipboard Image" : stem
    }

    private static func makeUniqueScratchPNGURL(stem: String, in directory: URL) -> URL {
        let fm = FileManager.default
        let primary = "\(stem).png"
        let primaryURL = directory.appendingPathComponent(primary)
        if !fm.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }
        var n = 1
        while n < 10_000 {
            let name: String
            if n == 1 {
                name = "\(stem) copy.png"
            } else {
                name = "\(stem) copy \(n).png"
            }
            let url = directory.appendingPathComponent(name)
            if !fm.fileExists(atPath: url.path) {
                return url
            }
            n += 1
        }
        return directory.appendingPathComponent("\(UUID().uuidString).png")
    }

    /// Places the clip on the pasteboard for picking from history or pasting into another app.
    func copyItemToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = item.imagePNGData, !png.isEmpty {
            copyImageToPasteboard(item: item, png: png, pb: pb)
        } else if let text = item.text {
            pb.setString(text, forType: .string)
        }
        lastChangeCount = pb.changeCount
    }

    private func copyImageToPasteboard(item: ClipboardItem, png: Data, pb: NSPasteboard) {
        let stem = Self.sanitizedImageStem(from: item.sourceFilename)
        let fileURL = Self.makeUniqueScratchPNGURL(stem: stem, in: Self.imagePasteScratchDir)
        do {
            try png.write(to: fileURL, options: .atomic)
        } catch {
            pb.setData(png, forType: .png)
            if let rep = NSBitmapImageRep(data: png),
               let tiff = rep.representation(using: .tiff, properties: [:]),
               !tiff.isEmpty {
                pb.setData(tiff, forType: .tiff)
            }
            return
        }

        let pasteItem = NSPasteboardItem()
        pasteItem.setData(png, forType: .png)
        if let rep = NSBitmapImageRep(data: png),
           let tiff = rep.representation(using: .tiff, properties: [:]),
           !tiff.isEmpty {
            pasteItem.setData(tiff, forType: .tiff)
        }
        pasteItem.setString(fileURL.absoluteString, forType: .fileURL)
        pasteItem.setPropertyList([fileURL.path], forType: Self.filenamesPboardType)
        pb.writeObjects([pasteItem])

        let urlToRemove = fileURL
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
            try? FileManager.default.removeItem(at: urlToRemove)
        }
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
