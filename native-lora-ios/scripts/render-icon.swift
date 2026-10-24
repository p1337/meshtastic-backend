import CoreGraphics
import ImageIO
import Foundation

// Direct RGB bitmap rendering also works without an AppKit/window-server context.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
context.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 220, y: 180, width: 584, height: 670), cornerWidth: 56, cornerHeight: 56, transform: nil)); context.fillPath()
context.setStrokeColor(CGColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)); context.setLineWidth(30); context.setLineCap(.round)
for y in [660.0, 735] { context.move(to: CGPoint(x: 310, y: y)); context.addLine(to: CGPoint(x: 650, y: y)); context.strokePath() }
context.setFillColor(CGColor(red: 1, green: 0.83, blue: 0.05, alpha: 1))
context.fillEllipse(in: CGRect(x: 300, y: 280, width: 424, height: 340))
context.setStrokeColor(CGColor(red: 1, green: 0.39, blue: 0.02, alpha: 1)); context.setLineWidth(65); context.setLineJoin(.round)
context.move(to: CGPoint(x: 355, y: 445)); context.addLine(to: CGPoint(x: 465, y: 345)); context.addLine(to: CGPoint(x: 680, y: 560)); context.strokePath()
// A blank bitmap or absent graphics context must never silently ship as an icon.
let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
var brightPixels = 0
for offset in stride(from: 0, to: size * size * 4, by: 4) {
    if max(bytes[offset], max(bytes[offset + 1], bytes[offset + 2])) > 160 { brightPixels += 1 }
}
precondition(brightPixels > 10000 && brightPixels < size * size * 3 / 4, "Icon is blank or invalid")
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
let output = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(output, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(output), "Could not write icon PNG")
print("Rendered opaque 1024px Werkbeleg document/check icon; verified nonblank RGB bitmap")
