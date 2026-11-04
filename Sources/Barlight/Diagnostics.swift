import AppKit
import Synchronization

/// `Barlight --dump-raw`: every extras bar child as AX reports it, unfiltered.
/// For investigating items the scanner skips, such as those behind the chevron.
enum Diagnostics {
    static func rawDump() -> String {
        let sections = Mutex(["trusted=\(AXIsProcessTrusted())"])
        let apps = NSWorkspace.shared.runningApplications
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = apps[index]
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.5)
            guard let bar = element(appElement, kAXExtrasMenuBarAttribute) else { return }

            var out = "== \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "-")] bar attrs: \(attributeNames(bar).joined(separator: ","))"
            for child in children(bar) {
                out += "\n  " + describe(child)
                // One level down, where some apps keep names and buttons.
                for inner in children(child) {
                    out += "\n      └ " + describe(inner)
                }
            }
            if let overflow = element(bar, "AXOverflowButton") {
                out += "\n  OVERFLOW " + describe(overflow)
                out += "\n    attrs: " + attributeNames(overflow).joined(separator: ",")
                for inner in children(overflow) {
                    out += "\n      └ " + describe(inner)
                }
            }
            sections.withLock { $0.append(out) }
        }
        return sections.withLock { $0.joined(separator: "\n") }
    }

    /// `Barlight --probe-overflow`: presses the » chevron and reports which
    /// extras bars appear while hidden items are revealed, then closes it.
    static func probeOverflow() -> String {
        var out: [String] = ["trusted=\(AXIsProcessTrusted())"]
        out.append("before: " + barSummary())

        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: ItemScanner.menuBarAgentBundleID).first,
              let bar = element(AXUIElementCreateApplication(agent.processIdentifier), kAXExtrasMenuBarAttribute),
              let chevron = children(bar).first(where: { string($0, kAXIdentifierAttribute) == "menu-bar-overflow-indicator" })
                ?? element(bar, "AXOverflowButton")
        else {
            out.append("no overflow chevron found")
            return out.joined(separator: "\n")
        }
        out.append("chevron: " + describe(chevron))
        out.append("press: \(AXUIElementPerformAction(chevron, kAXPressAction as CFString).rawValue)")

        for delay in [0.3, 0.8, 1.5] {
            Thread.sleep(forTimeInterval: delay == 0.3 ? 0.3 : 0.5)
            out.append("after \(delay)s: " + barSummary())
        }
        out.append("--- full dump while revealed ---")
        out.append(rawDump())

        out.append("close: \(AXUIElementPerformAction(chevron, kAXPressAction as CFString).rawValue)")
        Thread.sleep(forTimeInterval: 0.5)
        out.append("after close: " + barSummary())
        return out.joined(separator: "\n")
    }

    /// "App(children) …" for every app exposing an extras bar.
    private static func barSummary() -> String {
        NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.5)
            guard let bar = element(appElement, kAXExtrasMenuBarAttribute) else { return nil }
            return "\(app.localizedName ?? "?")(\(children(bar).count))"
        }.joined(separator: " ")
    }

    private static func describe(_ element: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let owner = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "\(pid)"
        return [
            string(element, kAXRoleAttribute) ?? "?",
            "title=\(string(element, kAXTitleAttribute) ?? "-")",
            "desc=\(string(element, kAXDescriptionAttribute) ?? "-")",
            "id=\(string(element, kAXIdentifierAttribute) ?? "-")",
            frameString(element),
            "owner=\(owner)",
            "actions=\(actionNames(element).joined(separator: ","))",
        ].joined(separator: " ")
    }

    private static func frameString(_ element: AXUIElement) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
              let position = ref
        else { return "noframe" }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success, let sizeValue = ref {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        return "x=\(Int(origin.x)) y=\(Int(origin.y)) w=\(Int(size.width)) h=\(Int(size.height))"
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        return (ref as! AXUIElement)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success else { return [] }
        return ref as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return (ref as? String)?.replacingOccurrences(of: "\n", with: " ")
    }

    private static func attributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        AXUIElementCopyAttributeNames(element, &names)
        return names as? [String] ?? []
    }

    private static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        return names as? [String] ?? []
    }
}
