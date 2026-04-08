import AppKit
import Foundation

enum ClipboardSettings {
    private static let autoCopyKey = "Clipboard.autoCopyScreenshots"

    static var autoCopyScreenshots: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoCopyKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: autoCopyKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoCopyKey) }
    }
}

/// Watches Desktop (and the user’s configured screenshot folder) for new macOS screenshot files and copies the image to the general pasteboard so history updates automatically.
@MainActor
final class ScreenshotClipboardWatcher {
    static let shared = ScreenshotClipboardWatcher()

    private var timer: Timer?
    private var didSeedExistingFiles = false
    /// Paths we have already reflected on the pasteboard, keyed by file path → content mod time when processed.
    private var processedModTimeByPath: [String: TimeInterval] = [:]

    private init() {}

    func applySettings() {
        if ClipboardSettings.autoCopyScreenshots {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard ClipboardSettings.autoCopyScreenshots else { return }
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        didSeedExistingFiles = false
        processedModTimeByPath.removeAll()
    }

    private func tick() {
        if !didSeedExistingFiles {
            seedExistingAsIgnored()
            didSeedExistingFiles = true
        }

        for dir in Self.watchDirectories() {
            scanDirectory(dir)
        }
        trimProcessedMapIfNeeded()
    }

    /// Mark everything that already looks like a screenshot as handled so we only react to new captures.
    private func seedExistingAsIgnored() {
        for dir in Self.watchDirectories() {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls {
                guard Self.looksLikeScreenshotFile(url) else { continue }
                guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      vals.isRegularFile == true,
                      let m = vals.contentModificationDate?.timeIntervalSince1970
                else { continue }
                processedModTimeByPath[url.path] = m
            }
        }
    }

    private func scanDirectory(_ dir: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls {
            guard Self.looksLikeScreenshotFile(url) else { continue }
            guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]),
                  vals.isRegularFile == true,
                  let mtime = vals.contentModificationDate?.timeIntervalSince1970
            else { continue }

            let path = url.path
            if let prev = processedModTimeByPath[path], abs(prev - mtime) < 0.000_001 { continue }

            guard let size = vals.fileSize, size > 64 else { continue }
            guard let img = NSImage(contentsOf: url) else { continue }
            guard let png = img.pngDataForClipboard(), !png.isEmpty else { continue }

            processedModTimeByPath[path] = mtime
            copyPNGToGeneralPasteboard(png, sourceFilename: url.lastPathComponent)
        }
    }

    private func copyPNGToGeneralPasteboard(_ png: Data, sourceFilename: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        if let rep = NSBitmapImageRep(data: png),
           let tiff = rep.representation(using: .tiff, properties: [:]),
           !tiff.isEmpty {
            pb.setData(tiff, forType: .tiff)
        }
        ClipboardStore.shared.ingestScreenshotImage(png: png, sourceFilename: sourceFilename)
    }

    private func trimProcessedMapIfNeeded() {
        guard processedModTimeByPath.count > 400 else { return }
        let keys = Array(processedModTimeByPath.keys.prefix(processedModTimeByPath.count / 2))
        for k in keys {
            processedModTimeByPath.removeValue(forKey: k)
        }
    }

    private static func watchDirectories() -> [URL] {
        var list: [URL] = []
        let fm = FileManager.default
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        list.append(desktop.standardizedFileURL)

        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = (path as NSString).expandingTildeInPath
            guard !expanded.isEmpty else { return list }
            let custom = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: custom.path, isDirectory: &isDir), isDir.boolValue,
               !list.contains(where: { $0.path == custom.path }) {
                list.append(custom)
            }
        }

        return list
    }

    /// Matches default English names and common variants; screenshots are usually `.png`.
    private static func looksLikeScreenshotFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "png" || ext == "jpg" || ext == "jpeg" else { return false }
        let name = url.lastPathComponent
        let lower = name.lowercased()
        if lower.hasPrefix("screenshot ") { return true }
        if lower.hasPrefix("screen shot ") { return true }
        if lower.hasPrefix("capture ") { return true }
        if lower.hasPrefix("bildschirmfoto ") { return true }
        return false
    }
}
