import Foundation

/// How Barlight finds items macOS has hidden behind the » chevron, which
/// Accessibility does not list while hidden.
enum HiddenItemsMode: String, CaseIterable {
    /// List items as last seen. Instant and invisible, but an item must have
    /// been visible once to be found.
    case remember
    /// Press » on every open to read the hidden items, then close it. Always
    /// complete and current, at the cost of a visible flash.
    case reveal

    var title: String {
        switch self {
        case .remember: "Remember items when seen"
        case .reveal: "Reveal with » on every open (no memory)"
        }
    }
}

/// User settings that are plain values. The hotkey lives in HotkeyCombo.saved.
enum Preferences {
    private static let includeSystemItemsKey = "includeSystemItems"
    private static let hiddenItemsModeKey = "hiddenItemsMode"

    /// Whether Apple's own items (Clock, Wi‑Fi, Sound…) are listed. Off by default.
    static var includeSystemItems: Bool {
        get { UserDefaults.standard.bool(forKey: includeSystemItemsKey) }
        set { UserDefaults.standard.set(newValue, forKey: includeSystemItemsKey) }
    }

    static var hiddenItemsMode: HiddenItemsMode {
        get { UserDefaults.standard.string(forKey: hiddenItemsModeKey).flatMap(HiddenItemsMode.init) ?? .remember }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: hiddenItemsModeKey) }
    }
}
