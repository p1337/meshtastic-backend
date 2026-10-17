import AppKit
import Foundation

// Deterministic project-native icon: a rising-frequency chirp and radio arcs.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                             bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let rect = NSRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
let gradient = NSGradient(starting: NSColor(srgbRed: 0.055, green: 0.105, blue: 0.17, alpha: 1),
                          ending: NSColor(srgbRed: 0.08, green: 0.24, blue: 0.28, alpha: 1))!
gradient.draw(in: rect, angle: 55)
let mint = NSColor(srgbRed: 0.46, green: 0.93, blue: 0.74, alpha: 1)
let blue = NSColor(srgbRed: 0.35, green: 0.66, blue: 1, alpha: 1)
let chirp = NSBezierPath()
for k in 0...900 {
    let t = Double(k) / 900
    let point = NSPoint(x: 155 + 714 * t, y: 405 + 105 * sin(2 * .pi * (1.2 * t + 3.8 * t * t)))
    if k == 0 { chirp.move(to: point) } else { chirp.line(to: point) }
}
chirp.lineCapStyle = .round; chirp.lineJoinStyle = .round
mint.withAlphaComponent(0.11).setStroke(); chirp.lineWidth = 55; chirp.stroke()
mint.setStroke(); chirp.lineWidth = 18; chirp.stroke()
for (radius, width) in [(110.0, 19.0), (185.0, 19.0), (260.0, 19.0)] {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: 512, y: 530), radius: radius, startAngle: 46, endAngle: 134)
    arc.lineCapStyle = .round; arc.lineWidth = width
    blue.withAlphaComponent(0.85).setStroke(); arc.stroke()
}
mint.setFill(); NSBezierPath(ovalIn: NSRect(x: 493, y: 554, width: 38, height: 38)).fill()
NSGraphicsContext.restoreGraphicsState()
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
print("Rendered opaque 1024px app icon")
