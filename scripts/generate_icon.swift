import AppKit

/// 绘制原创耳机与月牙标志，输出不含透明度的 App Store 图标。
func generateIcon(at path: String, pixels: Int = 1024) throws {
    let size = NSSize(width: 1024, height: 1024)
    let cg = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    cg.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(cgContext: cg, flipped: false)
    NSGraphicsContext.current = context
    NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.27, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    let glow = NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.40, alpha: 1), ending: NSColor(calibratedRed: 0.06, green: 0.23, blue: 0.23, alpha: 1))!
    glow.draw(in: NSBezierPath(rect: NSRect(origin: .zero, size: size)), angle: -65)
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 256, y: 440))
    line.curve(to: NSPoint(x: 768, y: 440), controlPoint1: NSPoint(x: 240, y: 860), controlPoint2: NSPoint(x: 784, y: 860))
    line.lineWidth = 42
    line.lineCapStyle = .round
    NSColor(calibratedRed: 0.88, green: 0.94, blue: 0.85, alpha: 1).setStroke()
    line.stroke()
    NSColor(calibratedRed: 0.88, green: 0.94, blue: 0.85, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 222, y: 332, width: 105, height: 205), xRadius: 48, yRadius: 48).fill()
    NSBezierPath(roundedRect: NSRect(x: 697, y: 332, width: 105, height: 205), xRadius: 48, yRadius: 48).fill()
    NSColor(calibratedRed: 0.95, green: 0.80, blue: 0.49, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 391, y: 350, width: 242, height: 242)).fill()
    NSColor(calibratedRed: 0.12, green: 0.33, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 455, y: 408, width: 214, height: 214)).fill()
    context.cgContext.flush()
    NSGraphicsContext.restoreGraphicsState()
    let bitmap = NSBitmapImageRep(cgImage: cg.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try generateIcon(at: output.path)
for points in [20, 29, 40, 60] {
    for scale in [2, 3] {
        try generateIcon(at: output.deletingLastPathComponent().appendingPathComponent("AppIcon-\(points)@\(scale)x.png").path, pixels: points * scale)
    }
}
