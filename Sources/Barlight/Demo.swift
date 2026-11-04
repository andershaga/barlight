import AppKit

/// `Barlight --demo`: the panel filled with made-up third-party apps instead
/// of a real scan, for screenshots that show nothing of the user's own apps.
/// Return does nothing and Accessibility is never queried.
enum Demo {
    static let isOn = CommandLine.arguments.contains("--demo")

    private struct Entry {
        let title: String
        let app: String
        let symbol: String
        let colors: (NSColor, NSColor)
        var hidden = false
    }

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static let entries: [Entry] = [
        Entry(title: "Clipboard History", app: "Clipper", symbol: "list.clipboard.fill", colors: (rgb(0xFFB340), rgb(0xFF7A00))),
        Entry(title: "CPU 12% · Memory 8.4 GB", app: "Gauge", symbol: "gauge.with.dots.needle.67percent", colors: (rgb(0x34C759), rgb(0x0E9F6E))),
        Entry(title: "Partly Cloudy 14°", app: "Skyline", symbol: "cloud.sun.fill", colors: (rgb(0x5AC8FA), rgb(0x007AFF))),
        Entry(title: "VPN Connected", app: "Tunnel", symbol: "lock.shield.fill", colors: (rgb(0x5E5CE6), rgb(0x3634A3))),
        Entry(title: "Focus Timer 18:42", app: "Tomato", symbol: "timer", colors: (rgb(0xFF6B6B), rgb(0xE0313B))),
        Entry(title: "Window Layouts", app: "Tiler", symbol: "rectangle.split.2x1.fill", colors: (rgb(0x64D2FF), rgb(0x0A84C6))),
        Entry(title: "Capture Screen", app: "Snapper", symbol: "camera.viewfinder", colors: (rgb(0x8E8E93), rgb(0x48484A))),
        Entry(title: "Color Picker", app: "Hue", symbol: "eyedropper.full", colors: (rgb(0xFF5EAA), rgb(0xBF5AF2))),
        Entry(title: "Quick Note", app: "Scribble", symbol: "note.text", colors: (rgb(0xFFD60A), rgb(0xF5A300))),
        Entry(title: "Next: Standup 10:00", app: "Agenda", symbol: "calendar", colors: (rgb(0xFF453A), rgb(0xC9302C)), hidden: true),
        Entry(title: "Keep Awake", app: "Brew", symbol: "cup.and.saucer.fill", colors: (rgb(0xC08552), rgb(0x8B5A2B)), hidden: true),
    ]

    /// Fake pids, negative so they never match a running app.
    static let items: [MenuBarItem] = entries.enumerated().map { index, entry in
        MenuBarItem(
            pid: -pid_t(index + 1), appName: entry.app, bundleID: "demo.\(index)",
            frame: .null, isOnScreen: !entry.hidden,
            axTitle: entry.title, axDescription: nil, axHelp: nil, axIdentifier: nil,
            element: entry.hidden ? nil : AXUIElementCreateSystemWide()
        )
    }

    /// A drawn app icon: gradient squircle with a white SF Symbol.
    static func icon(for item: MenuBarItem) -> NSImage? {
        guard isOn, item.pid < 0, entries.indices.contains(Int(-item.pid) - 1) else { return nil }
        let entry = entries[Int(-item.pid) - 1]
        let size: CGFloat = 64
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let tile = NSRect(x: 4, y: 4, width: size - 8, height: size - 8)
            let path = NSBezierPath(roundedRect: tile, xRadius: 13, yRadius: 13)
            NSGradient(colors: [entry.colors.0, entry.colors.1])?.draw(in: path, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let glyphSize = glyph.size
                glyph.draw(in: NSRect(
                    x: tile.midX - glyphSize.width / 2, y: tile.midY - glyphSize.height / 2,
                    width: glyphSize.width, height: glyphSize.height
                ))
            }
            return true
        }
    }
}
