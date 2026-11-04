// Draws the app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
//
// Layout follows Apple's macOS icon grid: 1024 canvas, 824 rounded square
// inset by 100, so macOS treats it as a standard-shaped icon.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let size: CGFloat = 1024

func drawIcon() -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

        // Drop shadow under the tile.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.shadowBlurRadius = 28
        shadow.set()
        NSColor.black.setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Background: deep blue to violet.
        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.33, green: 0.30, blue: 0.95, alpha: 1),
            NSColor(srgbRed: 0.10, green: 0.45, blue: 0.98, alpha: 1),
        ])!.draw(in: tile, angle: -70)

        // The menu bar: a frosted strip across the top with item "pills".
        let bar = NSRect(x: tile.minX, y: tile.maxY - 170, width: tile.width, height: 170)
        NSColor.white.withAlphaComponent(0.22).setFill()
        bar.fill()
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: 4).fill()

        let pillY = bar.midY - 22
        for (i, x) in [480.0, 590, 700, 790].enumerated() {
            let pill = NSRect(x: x, y: pillY, width: i == 1 ? 80 : 56, height: 44)
            // The second pill is the "found" item: bright, the rest dim.
            NSColor.white.withAlphaComponent(i == 1 ? 1 : 0.55).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 22, yRadius: 22).fill()
        }

        // Magnifying glass, centred below the bar, aimed up at the found item.
        let glassCenter = NSPoint(x: 470, y: 420)
        let radius: CGFloat = 150
        let lens = NSBezierPath(ovalIn: NSRect(
            x: glassCenter.x - radius, y: glassCenter.y - radius, width: radius * 2, height: radius * 2
        ))
        NSColor.white.withAlphaComponent(0.18).setFill()
        lens.fill()
        lens.lineWidth = 46
        NSColor.white.setStroke()
        lens.stroke()

        let handle = NSBezierPath()
        let angle = -CGFloat.pi / 4
        let start = NSPoint(x: glassCenter.x + cos(angle) * (radius + 20), y: glassCenter.y + sin(angle) * (radius + 20))
        handle.move(to: start)
        handle.line(to: NSPoint(x: start.x + 150 * cos(angle), y: start.y + 150 * sin(angle)))
        handle.lineWidth = 64
        handle.lineCapStyle = .round
        handle.stroke()

        NSGraphicsContext.restoreGraphicsState()
        return true
    }
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let icon = drawIcon()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(icon, pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(icon, pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()

// A full-size PNG next to it, for previews and the README.
try png(icon, pixels: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))
print(output.path)
