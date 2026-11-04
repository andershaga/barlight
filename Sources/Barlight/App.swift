import AppKit
import OSLog

let log = Logger(subsystem: "digital.haga.Barlight", category: "app")

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var searchHotkey: Hotkey?
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private let store = ItemStore()
    private let panel = SearchPanel()

    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--dump-raw") {
            print(Diagnostics.rawDump())
            return
        }
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
        if Demo.isOn {
            panel.onChoose = { _, _ in }
            panel.onOpenSettings = { [unowned self] in openSettings() }
            togglePanel()
            return
        }
        requestAccessibilityIfNeeded()

        store.onChange = { [unowned self] in panel.update(items: listedItems) }
        panel.onChoose = { [unowned self] item, alternate in
            Recents.record(item)
            store.whenChevronFree { Activator.open(item, alternate: alternate) }
        }
        panel.onOpenSettings = { [unowned self] in openSettings() }
        store.onRevealChanged = { [unowned self] revealing in panel.setRevealing(revealing) }
        store.refresh()

        // After the welcome window's restart, carry on to Settings.
        if CommandLine.arguments.contains("--open-settings") {
            openSettings()
        }
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
        if Demo.isOn {
            panel.show(items: Demo.items)
            return
        }
        panel.show(items: listedItems)
        store.refresh()
    }

    /// The scan minus Apple's items, unless Settings asks for them.
    private var listedItems: [MenuBarItem] {
        Preferences.includeSystemItems ? store.items : store.items.filter { !$0.isSystem }
    }

    /// Names and pressing need Accessibility; without it the first-run
    /// window explains why and waits for the grant.
    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let onboarding = OnboardingWindowController(
            hotkey: HotkeyCombo.saved.displayString,
            onFinish: { Self.relaunch(openingSettings: true) }
        )
        onboardingWindow = onboarding
        onboarding.show()
    }

    /// Quits and starts a fresh copy. Needed once after the Accessibility
    /// grant: apps queried before it keep refusing this process.
    ///
    /// A detached shell waits for this copy to exit, so the new one can
    /// register the hotkey.
    static func relaunch(openingSettings: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c", "sleep 0.5; /usr/bin/open -n \"$0\" --args \"$1\"",
            Bundle.main.bundlePath, openingSettings ? "--open-settings" : "--relaunched",
        ]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: Menu and Settings

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Template, so macOS tints it for light, dark and the selected state.
        let icon = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Barlight")
        icon?.isTemplate = true
        icon?.size = NSSize(width: 18, height: 18)
        icon?.accessibilityDescription = "Barlight"
        item.button?.image = icon

        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Barlight"))
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Barlight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                current: .saved,
                store: store,
                apply: { [unowned self] combo in register(combo) },
                setPaused: { [unowned self] paused in
                    if paused { searchHotkey?.unregister() } else { register(.saved) }
                }
            )
        }
        settingsWindow?.show()
    }
}
