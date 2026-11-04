import Carbon.HIToolbox

/// A system-wide hotkey registered through Carbon's RegisterEventHotKey.
///
/// Carbon is the only public API for global hotkeys that needs no
/// Accessibility or Input Monitoring permission.
@MainActor
final class Hotkey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandler: EventHandlerRef?

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    /// keyCode is a virtual key code (kVK_*); modifiers are Carbon masks (cmdKey, optionKey, ...).
    init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        Self.installEventHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x464D4249), id: id) // "FMBI"
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr else { return nil }
        Self.handlers[id] = handler
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        Self.handlers[id] = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            MainActor.assumeIsolated { Hotkey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
