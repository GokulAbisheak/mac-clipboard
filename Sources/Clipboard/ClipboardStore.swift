import AppKit
import Combine
import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let copiedAt: Date

    init(id: UUID = UUID(), text: String, copiedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
    }
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

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        if let first = items.first, first.text == text { return }

        let entry = ClipboardItem(text: text)
        items.insert(entry, at: 0)
        if items.count > Self.maxItems {
            items = Array(items.prefix(Self.maxItems))
        }
        scheduleSave()
    }

    /// Places `text` on the pasteboard (for picking from history).
    func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
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
