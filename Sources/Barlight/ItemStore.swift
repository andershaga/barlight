import AppKit

/// The last scan, so the panel can open instantly while a fresh scan
/// (about half a second) runs in the background.
///
/// Also remembers every app's items as last seen. macOS 27 drops items behind
/// the » chevron from Accessibility entirely, so for a running app that has
/// vanished from the scan, its remembered items are listed as hidden.
@MainActor
final class ItemStore {
    private(set) var items: [MenuBarItem] = []
    /// Called on the main actor after each finished scan.
    var onChange: (() -> Void)?
    /// Called with true just before » is pressed and false once it is closed,
    /// so the panel can ride out losing key focus in between.
    var onRevealChanged: ((Bool) -> Void)?
    private var isScanning = false
    private var remembered = RememberedItem.load()
    /// Remember mode opens » once per launch to learn items that were hidden
    /// before Barlight ever saw them; after that, memory alone is enough.
    private var didSeedThisLaunch = false

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        let screens = NSScreen.screens.map(\.frame)
        let mode = Preferences.hiddenItemsMode
        Task {
            let start = Date()
            let fresh = await Self.scan(screens: screens)

            switch mode {
            case .remember:
                items = merge(fresh)
                onChange?()
                if !didSeedThisLaunch, await Self.hasChevron() {
                    didSeedThisLaunch = true
                    onRevealChanged?(true)
                    let revealed = await Self.revealScan(screens: screens, visible: fresh)
                    onRevealChanged?(false)
                    items = merge(fresh, revealed: revealed.filter(\.isHidden))
                    onChange?()
                }
            case .reveal:
                // Visible items first, so the list fills while » is pressed.
                items = fresh
                onChange?()
                if await Self.hasChevron() {
                    onRevealChanged?(true)
                    items = await Self.revealScan(screens: screens, visible: fresh)
                    onRevealChanged?(false)
                    onChange?()
                }
            }
            log.notice("scan (\(mode.rawValue, privacy: .public)): \(fresh.count) visible, \(self.items.count - fresh.count) hidden, \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            isScanning = false
        }
    }

    /// How many items memory holds, across all apps (running or not).
    var rememberedCount: Int { remembered.values.reduce(0) { $0 + $1.count } }

    /// Forgets every remembered item, then rescans so the list drops them.
    func clearMemory() {
        remembered = [:]
        RememberedItem.save(remembered)
        didSeedThisLaunch = false
        items = items.filter { !$0.isHidden }
        onChange?()
        refresh()
    }

    @concurrent
    private nonisolated static func hasChevron() async -> Bool {
        ItemScanner.overflowChevron() != nil
    }

    /// Presses », rescans until the count settles, closes » again, and
    /// returns the visible items plus the newly revealed ones marked hidden.
    @concurrent
    private nonisolated static func revealScan(screens: [CGRect], visible: [MenuBarItem]) async -> [MenuBarItem] {
        guard let chevron = ItemScanner.overflowChevron(),
              AXUIElementPerformAction(chevron, kAXPressAction as CFString) == .success
        else { return visible }

        // Apps republish their bars over a few hundred ms; stop once stable.
        var revealed = visible
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(150))
            let scan = ItemScanner.scan(screens: screens)
            if scan.count == revealed.count, scan.count > visible.count { break }
            revealed = scan
        }

        if let chevron = ItemScanner.overflowChevron() {
            AXUIElementPerformAction(chevron, kAXPressAction as CFString)
        }

        let visibleApps = Set(visible.compactMap(\.bundleID))
        let hidden = revealed
            .filter { $0.bundleID.map { !visibleApps.contains($0) } ?? false }
            .map { $0.asHidden() }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return visible + hidden
    }

    /// Updates memory with what is visible (plus anything just read through
    /// »), then adds remembered items of running apps that showed nothing.
    private func merge(_ fresh: [MenuBarItem], revealed: [MenuBarItem] = []) -> [MenuBarItem] {
        let visible = Dictionary(grouping: fresh.filter { $0.bundleID != nil }, by: { $0.bundleID! })
        let seen = Dictionary(grouping: (fresh + revealed).filter { $0.bundleID != nil }, by: { $0.bundleID! })
        for (bundleID, list) in seen {
            remembered[bundleID] = list.map(RememberedItem.init)
        }
        RememberedItem.save(remembered)

        var running: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { running[id] = app }
        }
        let hidden = remembered
            .filter { visible[$0.key] == nil }
            .compactMap { bundleID, list in running[bundleID].map { app in list.map { $0.item(bundleID: bundleID, app: app) } } }
            .flatMap { $0 }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return fresh + hidden
    }

    @concurrent
    private nonisolated static func scan(screens: [CGRect]) async -> [MenuBarItem] {
        ItemScanner.scan(screens: screens)
    }
}

/// What is kept of an item between scans and launches.
private struct RememberedItem: Codable {
    var appName: String
    var axTitle: String?
    var axDescription: String?
    var axHelp: String?
    var axIdentifier: String?
    var duplicateNumber: Int?
    var indexInApp: Int

    init(_ item: MenuBarItem) {
        appName = item.appName
        axTitle = item.axTitle
        axDescription = item.axDescription
        axHelp = item.axHelp
        axIdentifier = item.axIdentifier
        duplicateNumber = item.duplicateNumber
        indexInApp = item.indexInApp
    }

    func item(bundleID: String, app: NSRunningApplication) -> MenuBarItem {
        var item = MenuBarItem(
            pid: app.processIdentifier, appName: appName, bundleID: bundleID,
            frame: .null, isOnScreen: false,
            axTitle: axTitle, axDescription: axDescription, axHelp: axHelp, axIdentifier: axIdentifier,
            element: nil
        )
        item.duplicateNumber = duplicateNumber
        item.indexInApp = indexInApp
        return item
    }

    private static let defaultsKey = "rememberedItems"

    static func load() -> [String: [RememberedItem]] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [RememberedItem]].self, from: data)
        else { return [:] }
        return decoded
    }

    static func save(_ items: [String: [RememberedItem]]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: defaultsKey)
    }
}
