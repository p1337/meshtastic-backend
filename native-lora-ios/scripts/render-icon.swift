import CoreGraphics
import ImageIO
import Foundation

// Direct RGB bitmap rendering also works without an AppKit/window-server context.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let colors = [CGColor(red: 0.055, green: 0.105, blue: 0.17, alpha: 1),
              CGColor(red: 0.08, green: 0.24, blue: 0.28, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                           end: CGPoint(x: size, y: size), options: [])
let chirp = CGMutablePath()
for k in 0...900 {
    let t = Double(k) / 900
    let point = CGPoint(x: 155 + 714 * t, y: 405 + 105 * sin(2 * .pi * (1.2 * t + 3.8 * t * t)))
    if k == 0 { chirp.move(to: point) } else { chirp.addLine(to: point) }
}
context.setLineCap(.round); context.setLineJoin(.round)
context.addPath(chirp)
context.setStrokeColor(CGColor(red: 0.46, green: 0.93, blue: 0.74, alpha: 0.11))
context.setLineWidth(55); context.strokePath()
context.addPath(chirp)
context.setStrokeColor(CGColor(red: 0.46, green: 0.93, blue: 0.74, alpha: 1))
context.setLineWidth(18); context.strokePath()
for radius in [110.0, 185, 260] {
    context.addArc(center: CGPoint(x: 512, y: 530), radius: radius,
                   startAngle: 46 * .pi / 180, endAngle: 134 * .pi / 180, clockwise: false)
    context.setStrokeColor(CGColor(red: 0.35, green: 0.66, blue: 1, alpha: 0.85))
    context.setLineWidth(19); context.strokePath()
}
context.setFillColor(CGColor(red: 0.46, green: 0.93, blue: 0.74, alpha: 1))
context.fillEllipse(in: CGRect(x: 493, y: 554, width: 38, height: 38))
// A blank bitmap or absent graphics context must never silently ship as an icon.
let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
var brightPixels = 0
for offset in stride(from: 0, to: size * size * 4, by: 4) {
    if max(bytes[offset], max(bytes[offset + 1], bytes[offset + 2])) > 160 { brightPixels += 1 }
}
precondition(brightPixels > 10000 && brightPixels < size * size / 2, "Icon is blank or invalid")
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
let output = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(output, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(output), "Could not write icon PNG")
print("Rendered opaque 1024px chirp icon; verified nonblank RGB bitmap")
