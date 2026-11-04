// Renders Resources/AppIcon.svg into Resources/AppIcon.icns and AppIcon.png.
// Run: swift scripts/make-icon.swift
//
// The SVG follows Apple's macOS icon grid: 1024 canvas, 824 rounded square
// inset by 100, so macOS treats it as a standard-shaped icon.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = try String(contentsOf: root.appendingPathComponent("Resources/AppIcon.svg"), encoding: .utf8)

func image(_ svg: String) -> NSImage {
    NSImage(data: Data(svg.utf8))!
}

let full = image(source)
// 16 and 32 px drop the background wave, which only adds noise that small.
let small = image(source.replacingOccurrences(
    of: #"<g id="02-depth-wave".*?</g>"#, with: "", options: .regularExpression
))

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try png(pixels <= 32 ? small : full, pixels: pixels).write(to: iconset.appendingPathComponent(name))
    }
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()

// A full-size PNG next to it, for previews and the README.
try png(full, pixels: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))
print(output.path)
