import AppKit
import ApplicationServices

enum PasteSimulator {
    /// Posts Command+V to the system event tap. Requires Accessibility permission for the app.
    static func pasteUsingCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    static func promptForAccessibilityIfNeeded() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
}
