import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalHotKey.shared.register()
        ClipboardStore.shared.startMonitoring()
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
