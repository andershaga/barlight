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
        // Querying apps before Accessibility is granted makes some of them
        // (Stats, Rectangle Pro…) keep refusing this process even after the
        // grant, until Barlight restarts. So list memory only until then.
        guard AXIsProcessTrusted() else {
            items = Preferences.hiddenItemsMode == .remember ? merge([]) : []
            onChange?()
            return
        }
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
            let hiddenApps = Set(items.filter(\.isHidden).map(\.appName)).sorted().joined(separator: ", ")
            log.notice("scan (\(mode.rawValue, privacy: .public)): \(fresh.count) visible, \(self.items.count - fresh.count) hidden [\(hiddenApps, privacy: .public)], \(Int(Date().timeIntervalSince(start) * 1000)) ms")
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

    /// Presses », reads the bar repeatedly, closes » again, and returns the
    /// visible items plus every newly revealed one marked hidden.
    ///
    /// Reads are combined rather than taking the last one, because an app
    /// that is slow to answer can drop out of any single read.
    @concurrent
    private nonisolated static func revealScan(screens: [CGRect], visible: [MenuBarItem]) async -> [MenuBarItem] {
        guard let chevron = ItemScanner.overflowChevron(),
              AXUIElementPerformAction(chevron, kAXPressAction as CFString) == .success
        else { return visible }

        let visibleKeys = Set(visible.map(\.identityKey))
        var found: [String: MenuBarItem] = [:]
        var quietReads = 0
        // At least three reads; then stop after two in a row add nothing.
        for read in 0..<8 {
            try? await Task.sleep(for: .milliseconds(150))
            var added = 0
            for item in ItemScanner.scan(screens: screens) where !visibleKeys.contains(item.identityKey) {
                if found.updateValue(item, forKey: item.identityKey) == nil { added += 1 }
            }
            quietReads = added == 0 ? quietReads + 1 : 0
            if read >= 2, quietReads >= 2 { break }
        }

        if let chevron = ItemScanner.overflowChevron() {
            AXUIElementPerformAction(chevron, kAXPressAction as CFString)
        }

        let hidden = found.values
            .map { $0.asHidden() }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return visible + hidden
    }

    /// Updates memory with what is visible (plus anything just read through
    /// »), then lists every remembered item of a running app that is not
    /// visible right now. Works per item, not per app: Stats can have two of
    /// its four items in the bar and two behind ».
    private func merge(_ fresh: [MenuBarItem], revealed: [MenuBarItem] = []) -> [MenuBarItem] {
        let seen = Dictionary(grouping: (fresh + revealed).filter { $0.bundleID != nil }, by: { $0.bundleID! })
        for (bundleID, list) in seen {
            let old = remembered[bundleID] ?? []
            // Fewer items than remembered usually means the rest are behind »
            // (a » read always sees the full set), so keep the unseen ones.
            let titles = Set(list.map(\.title))
            let kept = revealed.isEmpty && list.count < old.count
                ? old.filter { !titles.contains($0.title) }.prefix(old.count - list.count)
                : []
            remembered[bundleID] = list.map(RememberedItem.init) + kept
        }
        RememberedItem.save(remembered)

        var running: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { running[id] = app }
        }
        let visibleKeys = Set(fresh.map(\.identityKey))
        let hidden = remembered
            .compactMap { bundleID, list in running[bundleID].map { app in list.map { $0.item(bundleID: bundleID, app: app) } } }
            .flatMap { $0 }
            .filter { !visibleKeys.contains($0.identityKey) }
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

    /// Matches MenuBarItem.title for the same item.
    var title: String {
        item(bundleID: "", app: .current).title
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
