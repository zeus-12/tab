#!/usr/bin/env swift
// Generates Tab's app icon: a clean white "tab" glyph (⇥) on a flat black
// squircle. The glyph is Lucide's `arrow-right-to-line` icon (MIT licensed) —
// https://lucide.dev/icons/arrow-right-to-line — drawn with its exact path data
// and stroked with round caps/joins, so it matches the library 1:1.
//
// Reproducible — edit the constants below and re-run:
//
//     swift scripts/generate-icon.swift
//
// Output: Resources/AppIcon.icns (+ a 1024 PNG preview).
//
// Everything is expressed in a 1024×1024 design space and scaled per target
// size, so each PNG is rendered fresh (sharp) rather than downscaled.

import AppKit
import CoreGraphics
import Foundation

let bgColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)        // flat black
let glyphColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)     // white

// MARK: - Geometry

/// Apple-style continuous-corner squircle (superellipse) inscribed in `rect`.
func squirclePath(_ rect: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 1024
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * copysign(pow(abs(ct), 2 / n), ct)
        let y = cy + b * copysign(pow(abs(st), 2 / n), st)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

// Lucide `arrow-right-to-line` — exact 24×24 path data, mapped into design space
// and centered. SVG y grows downward, so we flip it to keep the arrow upright.
let glyphScale: CGFloat = 24.5            // 24-unit viewBox → design units
let glyphStroke: CGFloat = 2.25 * 24.5    // Lucide stroke-width, scaled up a touch

func glyphPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: 512 + (x - 12) * glyphScale, y: 512 - (y - 12) * glyphScale)
}

func tabGlyphPath() -> CGPath {
    let p = CGMutablePath()
    // M17 12 H3 — horizontal shaft
    p.move(to: glyphPoint(17, 12)); p.addLine(to: glyphPoint(3, 12))
    // m11 18 6-6 -6-6 — arrowhead chevron
    p.move(to: glyphPoint(11, 18)); p.addLine(to: glyphPoint(17, 12)); p.addLine(to: glyphPoint(11, 6))
    // M21 5 v14 — vertical bar
    p.move(to: glyphPoint(21, 5)); p.addLine(to: glyphPoint(21, 19))
    return p
}

// MARK: - Render one icon at `px` pixels

func renderIcon(px: Int) -> CGImage {
    let s = CGFloat(px) / 1024.0
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: s, y: s) // draw in 1024 design space

    // Flat black squircle
    ctx.addPath(squirclePath(CGRect(x: 100, y: 100, width: 824, height: 824)))
    ctx.setFillColor(bgColor)
    ctx.fillPath()

    // White stroked glyph
    ctx.setStrokeColor(glyphColor)
    ctx.setLineWidth(glyphStroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(tabGlyphPath())
    ctx.strokePath()

    return ctx.makeImage()!
}

// MARK: - Write PNG

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

// MARK: - Build the .iconset and run iconutil

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

var cache: [Int: CGImage] = [:]
for (name, size) in variants {
    let img = cache[size] ?? renderIcon(px: size)
    cache[size] = img
    writePNG(img, to: iconset.appendingPathComponent(name))
}

let resources = root.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let icns = resources.appendingPathComponent("AppIcon.icns")

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try! task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("✓ Wrote \(icns.path)")
    writePNG(cache[1024]!, to: resources.appendingPathComponent("AppIcon-preview.png"))
    print("✓ Wrote \(resources.appendingPathComponent("AppIcon-preview.png").path)")
    try? FileManager.default.removeItem(at: iconset)
} else {
    print("✗ iconutil failed (\(task.terminationStatus)); left \(iconset.path) in place")
    exit(1)
}
