import SwiftUI

@main
struct MacClipboardApp: App {
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
    @ObservedObject private var accessibility = AccessibilityPermissionCoordinator.shared
    @State private var launchAtLogin = LoginItemManager.isLaunchAtLoginEnabled

    var body: some View {
        Button("Show clipboard history (⌃⌘V)") {
            HistoryWindowController.shared.toggle(store: store)
        }
        Divider()
        Toggle("Open at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { v in
                LoginItemManager.isLaunchAtLoginEnabled = v
            }
            .onAppear {
                launchAtLogin = LoginItemManager.isLaunchAtLoginEnabled
            }
        Divider()
        if accessibility.showManualPasteButton {
            Button("Allow pasting into apps…") {
                accessibility.openAccessibilitySettingsPrompt()
            }
        }
        Button("Quit MacClipboard") {
            NSApplication.shared.terminate(nil)
        }
    }
}
