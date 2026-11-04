import AppKit
import OSLog

let log = Logger(subsystem: "digital.haga.Barlight", category: "app")

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var searchHotkey: Hotkey?
    private var settingsWindow: SettingsWindowController?
    private let store = ItemStore()
    private let panel = SearchPanel()

    static func main() {
        let app = NSApplication.shared
        // `--dump` prints one scan and exits; handy from a terminal.
        if CommandLine.arguments.contains("--dump") {
            let start = Date()
            let items = ItemScanner.scan(screens: NSScreen.screens.map(\.frame))
            print("scan took \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            print(ItemScanner.dump(items))
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        let combo = HotkeyCombo.saved
        if !register(combo) {
            log.error("could not register \(combo.displayString, privacy: .public); another app may own it")
        }
        requestAccessibilityIfNeeded()

        store.onChange = { [unowned self] in panel.update(items: listedItems) }
        panel.onChoose = { item in Self.open(item) }
        store.refresh()

        // Debug aid: open the panel at launch, for screenshots without a keypress.
        if CommandLine.arguments.contains("--show-panel") {
            togglePanel()
        }
        log.notice("launched")
    }

    // MARK: Hotkey

    /// Swaps the live hotkey for combo. On failure the previous one is put
    /// back, so the user is never left without a working hotkey.
    @discardableResult
    private func register(_ combo: HotkeyCombo) -> Bool {
        searchHotkey?.unregister()
        if let hotkey = Hotkey(keyCode: combo.keyCode, modifiers: combo.modifiers, handler: hotkeyPressed) {
            searchHotkey = hotkey
            HotkeyCombo.saved = combo
            log.notice("hotkey set to \(combo.displayString, privacy: .public)")
            return true
        }
        let previous = HotkeyCombo.saved
        searchHotkey = Hotkey(keyCode: previous.keyCode, modifiers: previous.modifiers, handler: hotkeyPressed)
        return false
    }

    private func hotkeyPressed() {
        togglePanel()
    }

    // MARK: Panel

    /// Shows the last scan at once and swaps in a fresh one when it lands.
    private func togglePanel() {
        if panel.isShowing {
            panel.dismiss()
            return
        }
        panel.show(items: listedItems)
        store.refresh()
    }

    /// The scan minus Apple's items, unless Settings asks for them.
    private var listedItems: [MenuBarItem] {
        Preferences.includeSystemItems ? store.items : store.items.filter { !$0.isSystem }
    }

    /// Temporary: a plain AXPress. Step 4 adds fallbacks and the right/left menu choice.
    /// Off the main thread, because some apps block AXPress until their menu closes.
    private static func open(_ item: MenuBarItem) {
        log.notice("opening \(item.title, privacy: .public) (\(item.appName, privacy: .public))")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
            if result != .success {
                log.error("AXPress failed for \(item.title, privacy: .public): \(result.rawValue)")
            }
        }
    }

    /// Names and pressing need Accessibility; without it the scan still lists
    /// windows, but only by app name.
    private func requestAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            log.notice("Accessibility not granted yet; prompted")
        }
    }

    // MARK: Menu and Settings

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Barlight")

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                current: .saved,
                apply: { [unowned self] combo in register(combo) },
                setPaused: { [unowned self] paused in
                    if paused { searchHotkey?.unregister() } else { register(.saved) }
                }
            )
        }
        settingsWindow?.show()
    }
}
