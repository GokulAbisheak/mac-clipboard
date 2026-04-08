import Combine
import Foundation

/// Drives automatic Accessibility prompting once, and shows a manual "Allow pasting" control only when still denied.
@MainActor
final class AccessibilityPermissionCoordinator: ObservableObject {
    static let shared = AccessibilityPermissionCoordinator()

    private static let autoPromptKey = "MacClipboard.accessibilityAutoPromptDone"
    private static let showManualKey = "MacClipboard.accessibilityShowManualPaste"

    @Published private(set) var isTrusted = false
    @Published private(set) var showManualPasteButton = false

    private init() {
        refresh()
    }

    func refresh() {
        let trusted = PasteSimulator.hasAccessibilityPermission
        isTrusted = trusted
        if trusted {
            UserDefaults.standard.set(false, forKey: Self.showManualKey)
            showManualPasteButton = false
            return
        }
        showManualPasteButton = UserDefaults.standard.bool(forKey: Self.showManualKey)
    }

    /// Call once at launch: first run shows the system prompt; later runs still without access show the manual control.
    static func runLaunchAccessibilityFlow() {
        guard !PasteSimulator.hasAccessibilityPermission else {
            UserDefaults.standard.set(false, forKey: showManualKey)
            shared.refresh()
            return
        }
        if !UserDefaults.standard.bool(forKey: autoPromptKey) {
            PasteSimulator.promptForAccessibilityIfNeeded()
            UserDefaults.standard.set(true, forKey: autoPromptKey)
        } else {
            UserDefaults.standard.set(true, forKey: showManualKey)
        }
        shared.refresh()
    }

    /// After the user dismisses the system sheet or switches away, offer the in-app shortcut if still untrusted.
    static func markManualButtonNeededIfStillUntrusted() {
        guard !PasteSimulator.hasAccessibilityPermission else { return }
        UserDefaults.standard.set(true, forKey: showManualKey)
        shared.refresh()
    }

    func openAccessibilitySettingsPrompt() {
        PasteSimulator.promptForAccessibilityIfNeeded()
    }
}
