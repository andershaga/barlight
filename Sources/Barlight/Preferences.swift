import Foundation

/// User settings that are plain flags. The hotkey lives in HotkeyCombo.saved.
enum Preferences {
    private static let includeSystemItemsKey = "includeSystemItems"

    /// Whether Apple's own items (Clock, Wi‑Fi, Sound…) are listed. Off by default.
    static var includeSystemItems: Bool {
        get { UserDefaults.standard.bool(forKey: includeSystemItemsKey) }
        set { UserDefaults.standard.set(newValue, forKey: includeSystemItemsKey) }
    }
}
