import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, stored in UserDefaults and handed to Hotkey.
struct HotkeyCombo: Codable, Equatable {
    /// Virtual key code (kVK_*).
    var keyCode: Int
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: Int
    /// What the key looked like when recorded, e.g. "1" or "K".
    var keyLabel: String

    /// ⇧⌘Space: Spotlight's ⌘Space plus Shift, so "Spotlight for the menu
    /// bar" is easy to remember, and unlike ⌘1 no app uses it for tabs.
    static let defaultSearch = HotkeyCombo(keyCode: kVK_Space, modifiers: cmdKey | shiftKey, keyLabel: "Space")

    /// Builds a combo from a key press, or nil when it has no ⌘, ⌥ or ⌃,
    /// since a bare key or ⇧-only key would swallow normal typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }

        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }

        let code = Int(event.keyCode)
        self.init(
            keyCode: code,
            modifiers: carbon,
            keyLabel: Self.specialKeyLabels[code]
                ?? event.charactersIgnoringModifiers?.uppercased()
                ?? "?"
        )
    }

    init(keyCode: Int, modifiers: Int, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// "⌃⌥⇧⌘K", in Apple's modifier order.
    var displayString: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + keyLabel
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

extension HotkeyCombo {
    private static let defaultsKey = "searchHotkey"

    static var saved: HotkeyCombo {
        get {
            guard let data = UserDefaults.standard.data(forKey: defaultsKey),
                  let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data)
            else { return .defaultSearch }
            return combo
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: defaultsKey)
        }
    }
}
