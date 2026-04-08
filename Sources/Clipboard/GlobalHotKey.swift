import AppKit
import Carbon

extension Notification.Name {
    static let toggleClipboardHistory = Notification.Name("toggleClipboardHistory")
}

private func globalHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    theEvent: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let theEvent else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        theEvent,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr else { return err }
    DispatchQueue.main.async {
        // Snapshot before our app steals focus from Finder / the target app (e.g. for desktop paste).
        let front = NSWorkspace.shared.frontmostApplication
        let pasteTarget: NSRunningApplication? = {
            guard let front else { return nil }
            return front.processIdentifier == NSRunningApplication.current.processIdentifier ? nil : front
        }()
        NotificationCenter.default.post(
            name: .toggleClipboardHistory,
            object: nil,
            userInfo: ["pasteTarget": pasteTarget as Any]
        )
    }
    return noErr
}

/// Global ⌃⌘V (Control + Command + V), similar to Windows Win+V.
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        // FourCharCode 'CLIP'
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4950), id: 1)
        let modifiers = UInt32(cmdKey | controlKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
    }
}
