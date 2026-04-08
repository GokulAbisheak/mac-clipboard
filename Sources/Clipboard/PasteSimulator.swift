import AppKit
import ApplicationServices

enum PasteSimulator {
    private static var didRequestAccessibilityPrompt = false

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
        AXIsProcessTrustedWithOptions(nil)
    }

    static func promptForAccessibilityIfNeeded() {
        guard !didRequestAccessibilityPrompt else { return }
        didRequestAccessibilityPrompt = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
