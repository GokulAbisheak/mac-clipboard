import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let copiedAt: Date
    var text: String?
    var imagePNGData: Data?
    var sourceFilename: String?
    var referencedFileURLs: [String]?

    init(
        id: UUID = UUID(),
        copiedAt: Date = Date(),
        text: String?,
        imagePNGData: Data?,
        sourceFilename: String? = nil,
        referencedFileURLs: [String]? = nil
    ) {
        self.id = id
        self.copiedAt = copiedAt
        self.text = text
        self.imagePNGData = imagePNGData
        self.sourceFilename = sourceFilename
        self.referencedFileURLs = referencedFileURLs
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
        referencedFileURLs = try c.decodeIfPresent([String].self, forKey: .referencedFileURLs)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(copiedAt, forKey: .copiedAt)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(imagePNGData, forKey: .imagePNGData)
        try c.encodeIfPresent(sourceFilename, forKey: .sourceFilename)
        try c.encodeIfPresent(referencedFileURLs, forKey: .referencedFileURLs)
    }

    private enum CodingKeys: String, CodingKey {
        case id, copiedAt, text, imagePNGData, sourceFilename, referencedFileURLs
    }

    var isImage: Bool { imagePNGData != nil }
    var isFileItems: Bool { referencedFileURLs.map { !$0.isEmpty } ?? false }

    /// One-line preview for the list.
    var previewText: String {
        if isFileItems, let refs = referencedFileURLs {
            return Self.fileListPreview(refs: refs)
        }
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

    private static func fileListPreview(refs: [String]) -> String {
        let urls = refs.compactMap { URL(string: $0) }
        guard !urls.isEmpty else { return "Files" }
        var dirCount = 0
        var fileCount = 0
        for u in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                dirCount += 1
            } else {
                fileCount += 1
            }
        }
        let firstName = urls[0].lastPathComponent
        let kind: String
        if dirCount > 0, fileCount == 0 {
            kind = urls.count == 1 ? "Folder" : "Folders"
        } else if fileCount > 0, dirCount == 0 {
            kind = urls.count == 1 ? "File" : "Files"
        } else {
            kind = "Items"
        }
        var s = "\(kind) · \(firstName)"
        if urls.count > 1 {
            s += " + \(urls.count - 1) more"
        }
        return s
    }
}

private extension NSImage {
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

func cgImageFromClipboardPNGData(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

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

        let existingFiles = collectExistingFileURLs(from: pb)
        if !existingFiles.isEmpty {
            let strings = existingFiles.map(\.absoluteString).sorted()
            if let first = items.first, first.referencedFileURLs == strings { return }
            let entry = ClipboardItem(
                text: nil,
                imagePNGData: nil,
                sourceFilename: nil,
                referencedFileURLs: strings
            )
            items.insert(entry, at: 0)
            trimAndSave()
            return
        }

        if let pair = readRasterImageFromPasteboard(pb), let png = pair.image.pngDataForClipboard() {
            if let first = items.first, first.imagePNGData == png, first.referencedFileURLs == nil { return }
            let entry = ClipboardItem(
                text: nil,
                imagePNGData: png,
                sourceFilename: pair.sourceFilename,
                referencedFileURLs: nil
            )
            items.insert(entry, at: 0)
            trimAndSave()
            return
        }

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        if let first = items.first, first.text == text, !first.isImage, !first.isFileItems { return }

        let entry = ClipboardItem(text: text, imagePNGData: nil, sourceFilename: nil, referencedFileURLs: nil)
        items.insert(entry, at: 0)
        trimAndSave()
    }

    private struct ImagePasteboardPair {
        let image: NSImage
        let sourceFilename: String?
    }

    /// Raster image only (TIFF/PNG/`NSImage`); file copies are handled as `referencedFileURLs` first.
    private func readRasterImageFromPasteboard(_ pb: NSPasteboard) -> ImagePasteboardPair? {
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

    private func collectExistingFileURLs(from pb: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        var seenPaths = Set<String>()

        func append(_ u: URL) {
            let std = u.standardizedFileURL
            guard std.isFileURL else { return }
            let path = std.path
            guard seenPaths.insert(path).inserted else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }
            urls.append(std)
        }

        if pb.canReadObject(forClasses: [NSURL.self], options: nil),
           let objects = pb.readObjects(forClasses: [NSURL.self], options: nil) {
            for obj in objects {
                if let u = obj as? URL {
                    append(u)
                } else if let n = obj as? NSURL {
                    append(n as URL)
                }
            }
        }

        if let s = pb.string(forType: .fileURL),
           let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            append(u)
        }

        if let paths = pb.propertyList(forType: Self.filenamesPboardType) as? [String] {
            for p in paths {
                append(URL(fileURLWithPath: p))
            }
        }

        for item in pb.pasteboardItems ?? [] {
            if let s = item.string(forType: .fileURL),
               let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                append(u)
            }
        }

        return urls
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

    private static func urlIsDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    func copyItemToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let refs = item.referencedFileURLs, !refs.isEmpty {
            copyFileItemsToPasteboard(refs: refs, pb: pb)
        } else if let png = item.imagePNGData, !png.isEmpty {
            copyImageToPasteboard(item: item, png: png, pb: pb)
        } else if let text = item.text {
            pb.setString(text, forType: .string)
        }
        lastChangeCount = pb.changeCount
    }

    private func copyFileItemsToPasteboard(refs: [String], pb: NSPasteboard) {
        let urls = refs.compactMap { URL(string: $0) }.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !urls.isEmpty else { return }

        let nsurls = urls.map { url in
            NSURL(fileURLWithPath: url.path, isDirectory: Self.urlIsDirectory(url))
        }
        pb.writeObjects(nsurls)
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
