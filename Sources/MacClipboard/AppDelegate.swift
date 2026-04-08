import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalHotKey.shared.register()
        ClipboardStore.shared.startMonitoring()
        LoginItemManager.syncOnLaunch()

        AccessibilityPermissionCoordinator.runLaunchAccessibilityFlow()

        NotificationCenter.default.addObserver(
            forName: .toggleClipboardHistory,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                HistoryWindowController.shared.toggle(store: ClipboardStore.shared)
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        AccessibilityPermissionCoordinator.markManualButtonNeededIfStillUntrusted()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AccessibilityPermissionCoordinator.shared.refresh()
    }
}
