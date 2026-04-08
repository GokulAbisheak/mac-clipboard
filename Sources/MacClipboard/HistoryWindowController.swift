import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = HistoryWindowController()

    private var window: NSWindow?
    private var hosting: NSHostingController<HistoryOverlayView>?
    private var keyboardState: HistoryOverlayKeyboardState?
    private var keyMonitor: Any?
    private var activationPolicyBeforeHistory: NSApplication.ActivationPolicy?

    private override init() {
        super.init()
    }

    func toggle(store: ClipboardStore) {
        if let w = window, w.isVisible {
            close()
            return
        }
        show(store: store)
    }

    func close() {
        window?.close()
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func teardownWindowResources() {
        removeKeyMonitor()
        keyboardState = nil
        hosting = nil
        window = nil
        restoreActivationPolicyAfterHistory()
    }

    func windowWillClose(_ notification: Notification) {
        teardownWindowResources()
    }

    private func show(store: ClipboardStore) {
        close()
        teardownWindowResources()

        let state = HistoryOverlayKeyboardState()
        state.selectedId = store.items.first?.id
        keyboardState = state

        let view = HistoryOverlayView(
            store: store,
            keyboardState: state,
            onDismiss: { [weak self] in self?.close() },
            onPaste: { [weak self] in self?.triggerPaste(store: store) }
        )
        let host = NSHostingController(rootView: view)
        hosting = host

        let rect = NSRect(x: 0, y: 0, width: 460, height: 560)
        let w = ClipboardKeyWindow(
            contentRect: rect,
            styleMask: [.borderless, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Clipboard"
        w.isOpaque = false
        w.backgroundColor = .clear
        w.isMovableByWindowBackground = true
        w.contentViewController = host
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.center()
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.delegate = self
        window = w

        installKeyMonitor(for: w, store: store)

        promoteAppForKeyboardFocus()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKey()

        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        host.view.layer?.borderWidth = 0
        host.view.layer?.masksToBounds = false
        w.contentView?.wantsLayer = true
        w.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        w.contentView?.layer?.borderWidth = 0

        DispatchQueue.main.async { [weak w, weak host] in
            guard let w, let host else { return }
            guard w.isVisible else { return }
            _ = w.makeFirstResponder(host.view)
        }

        if !PasteSimulator.hasAccessibilityPermission {
            PasteSimulator.promptForAccessibilityIfNeeded()
        }
    }

    /// Accessory apps do not receive key events for their windows; briefly use `.regular` while history is open.
    private func promoteAppForKeyboardFocus() {
        if activationPolicyBeforeHistory == nil {
            activationPolicyBeforeHistory = NSApp.activationPolicy()
        }
        if NSApp.activationPolicy() != .regular {
            _ = NSApp.setActivationPolicy(.regular)
        }
    }

    private func restoreActivationPolicyAfterHistory() {
        guard let previous = activationPolicyBeforeHistory else { return }
        activationPolicyBeforeHistory = nil
        _ = NSApp.setActivationPolicy(previous)
    }

    private func installKeyMonitor(for monitoredWindow: NSWindow, store: ClipboardStore) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard monitoredWindow.isKeyWindow else { return event }

            let code = Int(event.keyCode)
            switch code {
            case kVK_DownArrow:
                self.moveSelection(1, store: store)
                return nil
            case kVK_UpArrow:
                self.moveSelection(-1, store: store)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.triggerPaste(store: store)
                return nil
            default:
                return event
            }
        }
    }

    private func moveSelection(_ delta: Int, store: ClipboardStore) {
        guard let state = keyboardState else { return }
        let items = store.items
        guard !items.isEmpty else { return }

        let ids = items.map(\.id)
        let currentIndex: Int
        if let sid = state.selectedId, let idx = ids.firstIndex(of: sid) {
            currentIndex = idx
        } else {
            currentIndex = 0
        }

        let next = min(max(currentIndex + delta, 0), ids.count - 1)
        state.selectedId = ids[next]
    }

    private func triggerPaste(store: ClipboardStore) {
        guard let state = keyboardState,
              let id = state.selectedId,
              let item = store.items.first(where: { $0.id == id })
        else { return }

        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            store.copyToPasteboard(item.text)
            if PasteSimulator.hasAccessibilityPermission {
                PasteSimulator.pasteUsingCommandV()
            }
        }
    }
}
