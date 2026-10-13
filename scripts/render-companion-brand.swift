import AppKit
import Foundation

// Render the vector master directly at every macOS icon size. No original
// Assistant or iOS catalog is read or written by this script.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let catalog = root.appendingPathComponent("App/CompanionAssets.xcassets/CompanionIcon.appiconset")
let kit = root.appendingPathComponent("brandkit")
try FileManager.default.createDirectory(at: kit, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [CGFloat((hex >> 16) & 255) / 255,
                         CGFloat((hex >> 8) & 255) / 255,
                         CGFloat(hex & 255) / 255, 1])!
}

func mark() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 8, y: 5))
    for point in [CGPoint(x: 32, y: 5), CGPoint(x: 38, y: 11), CGPoint(x: 38, y: 28),
                  CGPoint(x: 28, y: 28), CGPoint(x: 25, y: 36), CGPoint(x: 20, y: 28),
                  CGPoint(x: 15, y: 36), CGPoint(x: 12, y: 28), CGPoint(x: 2, y: 28),
                  CGPoint(x: 2, y: 11)] { path.addLine(to: point) }
    path.closeSubpath()
    path.move(to: CGPoint(x: 10, y: 11))
    for point in [CGPoint(x: 8, y: 13), CGPoint(x: 8, y: 22), CGPoint(x: 32, y: 22),
                  CGPoint(x: 32, y: 13), CGPoint(x: 30, y: 11)] { path.addLine(to: point) }
    path.closeSubpath()
    path.addRect(CGRect(x: 12, y: 15, width: 6, height: 3))
    path.addRect(CGRect(x: 22, y: 15, width: 6, height: 3))
    return path
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Cannot render icon")
    }
    context.setShouldAntialias(true)
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    let tile = CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864),
                      cornerWidth: 194, cornerHeight: 194, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 22,
                      color: CGColor(gray: 0, alpha: 0.22))
    context.addPath(tile)
    context.setFillColor(color(0x16181B))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [color(0x303338), color(0x101113)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 80),
                               end: CGPoint(x: 512, y: 944), options: [])
    context.restoreGState()
    context.addPath(tile)
    context.setStrokeColor(color(0x4C4F54))
    context.setLineWidth(3)
    context.strokePath()
    context.saveGState()
    context.translateBy(x: 226, y: 226)
    context.scaleBy(x: 14.3, y: 14.3)
    context.addPath(mark())
    context.setFillColor(color(0xF4F4F2))
    context.drawPath(using: .eoFill)
    context.restoreGState()
    // A single red signal identifies the Mac companion within the Vamp family.
    context.setFillColor(color(0x1D1F22))
    context.fillEllipse(in: CGRect(x: 753, y: 748, width: 84, height: 84))
    context.setFillColor(color(0xD83546))
    context.fillEllipse(in: CGRect(x: 767, y: 762, width: 56, height: 56))
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: catalog.appendingPathComponent("icon_\(size).png"))
    if size == 1024 { try data.write(to: kit.appendingPathComponent("companion-icon.png")) }
}
print("Rendered Companion's seven macOS icon sizes from the Vamp vector mark.")
