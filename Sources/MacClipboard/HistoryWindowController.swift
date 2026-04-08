import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()

    private var window: NSWindow?
    private var hosting: NSHostingController<HistoryOverlayView>?

    private init() {}

    func toggle(store: ClipboardStore) {
        if let w = window, w.isVisible {
            close()
            return
        }
        show(store: store)
    }

    func close() {
        window?.close()
        window = nil
        hosting = nil
    }

    private func show(store: ClipboardStore) {
        close()

        let view = HistoryOverlayView(store: store) { [weak self] in
            self?.close()
        }
        let host = NSHostingController(rootView: view)
        hosting = host

        let rect = NSRect(x: 0, y: 0, width: 420, height: 520)
        let w = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "Clipboard"
        w.contentViewController = host
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.center()
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}
