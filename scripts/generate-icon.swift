#!/usr/bin/env swift

import AppKit
import CoreGraphics

let sizes: [(Int, String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

func generateIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let scale = CGFloat(size)

    // Background: dark rounded rect
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: scale * 0.22, yRadius: scale * 0.22)
    NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0).setFill()
    bgPath.fill()

    // Subtle orange radial glow behind the bulb
    let glowCenter = NSPoint(x: scale * 0.5, y: scale * 0.52)
    let glowRadius = scale * 0.35
    if let gradient = NSGradient(colors: [
        NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 0.25),
        NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 0.0),
    ]) {
        gradient.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: glowRadius, options: [])
    }

    // Lightbulb using SF Symbol
    let symbolSize = scale * 0.52
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .light)
    if let symbol = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {

        let symbolRect = symbol.size
        let x = (scale - symbolRect.width) / 2
        let y = (scale - symbolRect.height) / 2 + scale * 0.02 // nudge up slightly

        // Draw with orange color
        let tinted = NSImage(size: symbolRect)
        tinted.lockFocus()
        NSColor(red: 1.0, green: 0.65, blue: 0.25, alpha: 1.0).set()
        symbol.draw(in: NSRect(origin: .zero, size: symbolRect),
                    from: NSRect(origin: .zero, size: symbol.size),
                    operation: .sourceOver, fraction: 1.0)

        // Apply color by drawing over with source atop
        NSColor(red: 1.0, green: 0.65, blue: 0.25, alpha: 1.0).set()
        NSRect(origin: .zero, size: symbolRect).fill(using: .sourceAtop)
        tinted.unlockFocus()

        tinted.draw(in: NSRect(x: x, y: y, width: symbolRect.width, height: symbolRect.height),
                    from: NSRect(origin: .zero, size: symbolRect),
                    operation: .sourceOver, fraction: 1.0)
    }

    img.unlockFocus()
    return img
}

// Create iconset directory
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let iconsetPath = projectDir.appendingPathComponent("build/Erdos.iconset")

let fm = FileManager.default
try? fm.removeItem(at: iconsetPath)
try fm.createDirectory(at: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = generateIcon(size: size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    let pngData = rep.representation(using: .png, properties: [:])!
    let filePath = iconsetPath.appendingPathComponent("\(name).png")
    try pngData.write(to: filePath)
    print("Generated \(name).png (\(size)x\(size))")
}

// Convert to icns
let icnsPath = projectDir.appendingPathComponent("build/Erdos.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath.path, "-o", icnsPath.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("\nCreated: \(icnsPath.path)")
} else {
    print("iconutil failed with status \(process.terminationStatus)")
}
