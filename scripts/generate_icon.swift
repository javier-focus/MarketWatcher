#!/usr/bin/env swift
/// generate_icon.swift
/// Renders MarketWatcher app icons at every required macOS size.
///
/// Usage (from repo root):
///   swift scripts/generate_icon.swift
///
/// Output:
///   MarketWatcher/Sources/SP500Widget/Assets.xcassets/AppIcon.appiconset/icon_*.png

import AppKit
import CoreGraphics

// MARK: - Design tokens

let bgColor   = NSColor(red: 0x1C/255.0, green: 0x1C/255.0, blue: 0x1E/255.0, alpha: 1)  // #1C1C1E
let lineColor = NSColor(red: 0x30/255.0, green: 0xD1/255.0, blue: 0x58/255.0, alpha: 1)   // #30D158

// MARK: - Required sizes  (pt, scale) → filename

let sizes: [(Int, Int, String)] = [
    (16,  1, "icon_16x16.png"),
    (16,  2, "icon_16x16@2x.png"),
    (32,  1, "icon_32x32.png"),
    (32,  2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

// MARK: - Render

let outputDir = "MarketWatcher/Sources/SP500Widget/Assets.xcassets/AppIcon.appiconset"

for (pt, scale, filename) in sizes {
    let px   = pt * scale
    let size = CGSize(width: px, height: px)

    let image = NSImage(size: size)
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        print("❌  No graphics context for \(filename)")
        image.unlockFocus()
        continue
    }

    let s = CGFloat(px)

    // ── Background: rounded rect ────────────────────────────────────────────
    let radius = s * 0.22      // macOS icon squircle approximation
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let path   = CGPath(roundedRect: bgRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(bgColor.cgColor)
    ctx.fillPath()

    // ── Chart line (uptrend sparkline) ──────────────────────────────────────
    // Points expressed as fractions of the icon size, then scaled.
    // The line mimics a simple upward-trending sparkline with a small dip.
    let margin = s * 0.18
    let chartW = s - margin * 2
    let chartH = s * 0.38
    let baseY  = s * 0.56      // vertical centre of the chart area

    let pts: [(CGFloat, CGFloat)] = [
        (0.00,  0.00),   // start at baseline
        (0.14, -0.12),
        (0.28,  0.08),
        (0.42, -0.20),
        (0.56, -0.35),
        (0.70, -0.55),
        (0.84, -0.70),
        (1.00, -1.00),   // peak at top-right
    ]

    let linePts = pts.map { CGPoint(x: margin + $0.0 * chartW,
                                    y: baseY  + $0.1 * chartH) }

    // Filled area under the line (gradient effect via semi-transparent fill)
    let areaPth = CGMutablePath()
    areaPth.move(to: CGPoint(x: linePts[0].x, y: baseY + chartH * 0.2))
    linePts.forEach { areaPth.addLine(to: $0) }
    areaPth.addLine(to: CGPoint(x: linePts.last!.x, y: baseY + chartH * 0.2))
    areaPth.closeSubpath()
    ctx.addPath(areaPth)
    ctx.setFillColor(lineColor.withAlphaComponent(0.25).cgColor)
    ctx.fillPath()

    // The line itself
    let lineWidth = max(1.5, s * 0.03)
    ctx.setStrokeColor(lineColor.cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let linePth = CGMutablePath()
    linePth.move(to: linePts[0])
    linePts.dropFirst().forEach { linePth.addLine(to: $0) }
    ctx.addPath(linePth)
    ctx.strokePath()

    image.unlockFocus()

    // Write PNG
    guard
        let tiff = image.tiffRepresentation,
        let bmp  = NSBitmapImageRep(data: tiff),
        let png  = bmp.representation(using: .png, properties: [:])
    else {
        print("❌  Could not encode \(filename)")
        continue
    }

    let url = URL(fileURLWithPath: "\(outputDir)/\(filename)")
    do {
        try png.write(to: url)
        print("✅  \(filename)  (\(px)×\(px) px)")
    } catch {
        print("❌  \(filename): \(error)")
    }
}

print("\nDone. Icons written to \(outputDir)/")
