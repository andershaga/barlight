import AppKit
import ApplicationServices

/// One menu bar item (status item or system module).
///
/// Unchecked Sendable because of AXUIElement, which is safe to read from any thread.
struct MenuBarItem: @unchecked Sendable {
    let pid: pid_t
    let appName: String
    let bundleID: String?
    /// In global top-left-origin screen coordinates, as AX reports it.
    let frame: CGRect
    let isOnScreen: Bool
    let axTitle: String?
    let axDescription: String?
    let axHelp: String?
    let axIdentifier: String?
    /// The element to press; nil for a remembered item hidden behind ».
    let element: AXUIElement?
    /// Set when the same app shows several items with the same name.
    var duplicateNumber: Int?
    /// Position among its app's items, right to left. Finds a hidden item
    /// again when its name has changed ("Disconnected" → "Connected").
    var indexInApp = 0

    /// Not in the menu bar right now: macOS moved it behind the » chevron.
    var isHidden: Bool { element == nil }

    /// Tells items apart across scans: app plus the title the list shows.
    var identityKey: String { "\(bundleID ?? appName)|\(title)" }

    /// Apple's own items: MenuBarAgent modules, the input menu and the like.
    var isSystem: Bool { bundleID?.hasPrefix("com.apple.") ?? false }

    /// Best human name: AX title, then description, then help, then the app name.
    var name: String {
        [axTitle, axDescription, axHelp].lazy
            .compactMap { $0 }
            .map { $0.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " · ") }
            .first { !$0.isEmpty } ?? appName
    }

    /// What the list shows: name, numbered when it repeats ("Badgeify 2").
    var title: String {
        duplicateNumber.map { "\(name) \($0)" } ?? name
    }

    /// The same item marked hidden: its element dies once » closes.
    func asHidden() -> MenuBarItem {
        var copy = MenuBarItem(
            pid: pid, appName: appName, bundleID: bundleID, frame: .null, isOnScreen: false,
            axTitle: axTitle, axDescription: axDescription, axHelp: axHelp, axIdentifier: axIdentifier,
            element: nil
        )
        copy.duplicateNumber = duplicateNumber
        copy.indexInApp = indexInApp
        return copy
    }
}

/// Lists menu bar items through Accessibility.
///
/// On macOS 27 status items are no longer separate windows other processes
/// can see, so AX is the only public source: every app's AXExtrasMenuBar,
/// plus com.apple.MenuBarAgent, which hosts the system items (each an AXGroup)
/// and the overflow chevron (a bare AXButton, skipped).
enum ItemScanner {
    static let menuBarAgentBundleID = "com.apple.MenuBarAgent"

    /// Per-app AX timeout, so one hung app cannot stall the scan.
    private static let axTimeout: Float = 0.5

    /// Queries every running app in parallel: each AX round trip costs ~20 ms,
    /// and a machine runs over 100 apps, most of which have no extras bar.
    ///
    /// Safe off the main thread; pass NSScreen frames, which are main-thread API.
    static func scan(screens: [CGRect]) -> [MenuBarItem] {
        let ownBundleID = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier != ownBundleID || ownBundleID == nil
        }
        let primaryHeight = screens.first?.height ?? 0

        let results = LockedArray()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            results.append(contentsOf: items(of: apps[index], ownBundleID: ownBundleID, screens: screens, primaryHeight: primaryHeight))
        }
        // Right to left, the way people read the menu bar.
        return numberDuplicates(results.values.sorted { $0.frame.minX > $1.frame.minX })
    }

    /// The items of one app, right to left; used while waiting for a hidden
    /// item to reappear.
    static func items(bundleID: String) -> [MenuBarItem] {
        let ownBundleID = Bundle.main.bundleIdentifier
        let found = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).flatMap {
            items(of: $0, ownBundleID: ownBundleID, screens: [], primaryHeight: 0)
        }
        return numberDuplicates(found.sorted { $0.frame.minX > $1.frame.minX })
    }

    /// The » button that reveals items macOS has hidden for lack of space.
    static func overflowChevron() -> AXUIElement? {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: menuBarAgentBundleID).first
        else { return nil }
        let appElement = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, axTimeout)
        guard let bar: AXUIElement = value(appElement, kAXExtrasMenuBarAttribute) else { return nil }
        if let button: AXUIElement = value(bar, "AXOverflowButton") { return button }
        let children: [AXUIElement] = value(bar, kAXChildrenAttribute) ?? []
        return children.first { string($0, kAXIdentifierAttribute) == "menu-bar-overflow-indicator" }
            ?? children.first { string($0, kAXRoleAttribute) == kAXButtonRole }
    }

    /// Numbers names that repeat within one app and records each item's
    /// position in its app. Per app, so another app's item with the same name
    /// cannot shift these titles, which identityKey is built from.
    private static func numberDuplicates(_ items: [MenuBarItem]) -> [MenuBarItem] {
        func appKey(_ item: MenuBarItem) -> String { item.bundleID ?? "\(item.pid)" }
        func nameKey(_ item: MenuBarItem) -> String { "\(appKey(item))|\(item.name)" }
        let counts = Dictionary(grouping: items, by: nameKey).mapValues(\.count)
        var seen: [String: Int] = [:]
        var perApp: [String: Int] = [:]
        return items.map { item in
            var copy = item
            copy.indexInApp = perApp[appKey(item), default: 0]
            perApp[appKey(item), default: 0] += 1
            let key = nameKey(item)
            if counts[key, default: 0] > 1 {
                seen[key, default: 0] += 1
                copy.duplicateNumber = seen[key]
            }
            return copy
        }
    }

    private static func items(
        of app: NSRunningApplication, ownBundleID: String?, screens: [CGRect], primaryHeight: CGFloat
    ) -> [MenuBarItem] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, axTimeout)
        guard let bar: AXUIElement = value(appElement, kAXExtrasMenuBarAttribute) else { return [] }

        let isAgent = app.bundleIdentifier == menuBarAgentBundleID
        let overflow: AXUIElement? = value(bar, "AXOverflowButton")
        let children: [AXUIElement] = value(bar, kAXChildrenAttribute) ?? []
        var items: [MenuBarItem] = []

        for child in children {
            if let overflow, CFEqual(overflow, child) { continue }
            if isAgent, string(child, kAXRoleAttribute) == kAXButtonRole { continue }
            guard let frame = axFrame(child), !frame.isEmpty else { continue }

            // MenuBarAgent hosts other apps' items; the element knows its real owner.
            var ownerPID = app.processIdentifier
            if isAgent { AXUIElementGetPid(child, &ownerPID) }
            let owner = ownerPID == app.processIdentifier ? app : NSRunningApplication(processIdentifier: ownerPID)
            if let ownBundleID, owner?.bundleIdentifier == ownBundleID { continue }
            let ownerIsSystem = owner?.bundleIdentifier?.hasPrefix("com.apple.") ?? false

            // MenuBarAgent wraps each item in an AXGroup with no actions; the
            // pressable AXMenuBarItem and its name sit one level down.
            let inner: [AXUIElement] = value(child, kAXChildrenAttribute) ?? []
            let target = string(child, kAXRoleAttribute) == kAXGroupRole
                ? inner.first { string($0, kAXRoleAttribute) == kAXMenuBarItemRole } ?? child
                : child
            let description = string(target, kAXDescriptionAttribute)
                ?? string(child, kAXDescriptionAttribute)
                ?? inner.lazy.compactMap { string($0, kAXDescriptionAttribute) }.first

            // AX uses a top-left origin on the primary screen; NSScreen uses bottom-left.
            let appKitFrame = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)

            items.append(MenuBarItem(
                pid: ownerPID,
                appName: ownerIsSystem ? "System" : owner?.localizedName ?? app.localizedName ?? "pid \(ownerPID)",
                bundleID: owner?.bundleIdentifier,
                frame: frame,
                isOnScreen: screens.contains { $0.insetBy(dx: 0, dy: -1).intersects(appKitFrame) },
                axTitle: string(target, kAXTitleAttribute),
                axDescription: description,
                axHelp: string(target, kAXHelpAttribute),
                axIdentifier: string(target, kAXIdentifierAttribute),
                element: target
            ))
        }
        return items
    }

    // MARK: AX helpers

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let posValue: AXValue = value(element, kAXPositionAttribute),
              let sizeValue: AXValue = value(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let s: String = value(element, attribute), !s.isEmpty else { return nil }
        return s
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? T
    }
}

/// Collects results from concurrentPerform workers.
private final class LockedArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MenuBarItem] = []

    func append(contentsOf items: [MenuBarItem]) {
        guard !items.isEmpty else { return }
        lock.withLock { storage.append(contentsOf: items) }
    }

    var values: [MenuBarItem] { lock.withLock { storage } }
}

extension ItemScanner {
    /// Human-readable table for the spike: one line per item.
    static func dump(_ items: [MenuBarItem]) -> String {
        var lines = ["\(items.count) items, trusted=\(AXIsProcessTrusted())"]
        for item in items {
            lines.append(String(
                format: "%@ %-30@ app=%-22@ x=%5.0f w=%3.0f id=%@",
                item.isHidden ? "»" : item.isOnScreen ? "●" : "○",
                item.title as NSString,
                item.appName as NSString,
                item.frame.minX, item.frame.width,
                (item.axIdentifier ?? "-") as NSString
            ))
        }
        return lines.joined(separator: "\n")
    }
}
