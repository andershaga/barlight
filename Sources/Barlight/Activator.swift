import AppKit

/// Opens a menu bar item's menu.
///
/// Runs off the main thread: some apps block AXPress until their menu closes.
enum Activator {
    /// How long a hidden item gets to reappear after » is pressed.
    private static let revealTimeout: TimeInterval = 2
    private static let pollInterval: TimeInterval = 0.1

    /// alternate asks for the right-click menu (⌥Return) instead of the normal one.
    static func open(_ item: MenuBarItem, alternate: Bool = false) {
        log.notice("opening \(item.title, privacy: .public) (\(item.appName, privacy: .public))\(item.isHidden ? " via »" : "", privacy: .public)\(alternate ? " [right-click]" : "", privacy: .public)")
        DispatchQueue.global(qos: .userInitiated).async {
            if let element = item.element {
                press(element, item, alternate: alternate)
            } else {
                openHidden(item, alternate: alternate)
            }
        }
    }

    /// Presses » so macOS shows the hidden items, waits for this one to
    /// appear in Accessibility again, then presses it.
    private static func openHidden(_ item: MenuBarItem, alternate: Bool) {
        guard let bundleID = item.bundleID, let chevron = ItemScanner.overflowChevron() else {
            log.error("no » chevron to reveal \(item.title, privacy: .public)")
            return
        }
        let result = AXUIElementPerformAction(chevron, kAXPressAction as CFString)
        guard result == .success else {
            log.error("pressing » failed: \(result.rawValue)")
            return
        }

        let deadline = Date().addingTimeInterval(revealTimeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)
            if let match = bestMatch(for: item, in: ItemScanner.items(bundleID: bundleID)), let element = match.element {
                press(element, item, alternate: alternate)
                return
            }
        }
        log.error("\(item.title, privacy: .public) did not appear within \(revealTimeout)s of pressing »")
    }

    /// The live item that is the remembered one. Names can change while
    /// hidden ("Disconnected" → "Connected"), so position is the last resort.
    private static func bestMatch(for item: MenuBarItem, in live: [MenuBarItem]) -> MenuBarItem? {
        if let id = item.axIdentifier, let match = live.first(where: { $0.axIdentifier == id }) { return match }
        if let match = live.first(where: { $0.title == item.title }) { return match }
        if live.indices.contains(item.indexInApp) { return live[item.indexInApp] }
        return live.count == 1 ? live[0] : nil
    }

    private static func press(_ element: AXUIElement, _ item: MenuBarItem, alternate: Bool) {
        if alternate, showSecondaryMenu(element) { return }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result != .success {
            log.error("AXPress failed for \(item.title, privacy: .public): \(result.rawValue)")
        }
    }

    /// The right-click menu: AXShowMenu where the item offers it (system
    /// items do), else a synthetic right-click on the item. Third-party items
    /// expose only AXPress, so the click is the only way to their second menu.
    private static func showSecondaryMenu(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        if (names as? [String] ?? []).contains(kAXShowMenuAction),
           AXUIElementPerformAction(element, kAXShowMenuAction as CFString) == .success {
            return true
        }
        guard let frame = frame(of: element), !frame.isEmpty else { return false }
        return rightClick(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Posts a right-click, then puts the pointer back where it was.
    private static func rightClick(at point: CGPoint) -> Bool {
        let original = CGEvent(source: nil)?.location
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right),
              let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
        else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        if let original { CGWarpMouseCursorPosition(original) }
        return true
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size
        else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}
