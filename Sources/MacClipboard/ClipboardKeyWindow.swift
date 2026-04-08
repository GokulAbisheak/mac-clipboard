import AppKit

/// Ensures the history window can become key so keyboard events stay in this app instead of the previous app.
final class ClipboardKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { true }
}
