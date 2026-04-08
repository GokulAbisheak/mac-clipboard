import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.module.url(forResource: "clipboard", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }

        GlobalHotKey.shared.register()
        ClipboardStore.shared.startMonitoring()
        ScreenshotClipboardWatcher.shared.applySettings()
        LoginItemManager.syncOnLaunch()

        NotificationCenter.default.addObserver(
            forName: .toggleClipboardHistory,
            object: nil,
            queue: .main
        ) { note in
            let target = note.userInfo?["pasteTarget"] as? NSRunningApplication
            Task { @MainActor in
                HistoryWindowController.shared.toggle(store: ClipboardStore.shared, hotkeyPasteTarget: target)
            }
        }
    }

}
