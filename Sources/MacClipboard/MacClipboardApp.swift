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
        if !PasteSimulator.hasAccessibilityPermission {
            Button("Allow pasting into apps…") {
                PasteSimulator.promptForAccessibilityIfNeeded()
            }
        }
        Button("Quit MacClipboard") {
            NSApplication.shared.terminate(nil)
        }
    }
}
