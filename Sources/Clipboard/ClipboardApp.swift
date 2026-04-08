import SwiftUI

@main
struct ClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Clipboard", systemImage: "doc.on.clipboard") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContentView: View {
    @ObservedObject private var store = ClipboardStore.shared
    @State private var launchAtLogin = LoginItemManager.isLaunchAtLoginEnabled
    @AppStorage("Clipboard.autoCopyScreenshots") private var autoCopyScreenshots = true

    var body: some View {
        Button("Show clipboard history (⇧⌘V)", systemImage: "list.bullet.rectangle.portrait") {
            HistoryWindowController.shared.toggle(store: store)
        }
        Divider()
        Toggle(isOn: $autoCopyScreenshots) {
            Label("Auto-copy screenshots", systemImage: "camera.viewfinder")
        }
        .onChange(of: autoCopyScreenshots) { _ in
            ScreenshotClipboardWatcher.shared.applySettings()
        }
        Divider()
        Toggle(isOn: $launchAtLogin) {
            Label("Open at login", systemImage: "powerplug.portrait.fill")
        }
            .onChange(of: launchAtLogin) { v in
                LoginItemManager.isLaunchAtLoginEnabled = v
            }
            .onAppear {
                launchAtLogin = LoginItemManager.isLaunchAtLoginEnabled
            }
        Divider()
        Button("Quit Clipboard", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
    }
}
