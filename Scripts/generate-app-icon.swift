#!/usr/bin/env swift

import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let repositoryURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputURL = repositoryURL
    .appendingPathComponent("Son/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(
    at: outputURL,
    withIntermediateDirectories: true
)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let canvas = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "SonIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

    let inset = canvas * 0.0625
    let background = NSBezierPath(
        roundedRect: NSRect(
            x: inset,
            y: inset,
            width: canvas - (inset * 2),
            height: canvas - (inset * 2)
        ),
        xRadius: canvas * 0.22,
        yRadius: canvas * 0.22
    )
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    background.fill()

    let trackStart = canvas * 0.22
    let trackEnd = canvas * 0.78
    let lineWidth = max(1, canvas * 0.042)
    let knobRadius = canvas * 0.066
    let tracks: [(y: CGFloat, knobX: CGFloat)] = [
        (canvas * 0.69, canvas * 0.40),
        (canvas * 0.50, canvas * 0.64),
        (canvas * 0.31, canvas * 0.48),
    ]

    for track in tracks {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: trackStart, y: track.y))
        line.line(to: NSPoint(x: trackEnd, y: track.y))
        line.lineWidth = lineWidth
        line.lineCapStyle = .round
        NSColor(calibratedWhite: 1, alpha: 0.38).setStroke()
        line.stroke()

        let knob = NSBezierPath(
            ovalIn: NSRect(
                x: track.knobX - knobRadius,
                y: track.y - knobRadius,
                width: knobRadius * 2,
                height: knobRadius * 2
            )
        )
        NSColor.white.setFill()
        knob.fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SonIcon", code: 2)
    }

    try png.write(to: outputURL.appendingPathComponent("AppIcon-\(size).png"))
}

print("Generated Son app icons in \(outputURL.path)")
