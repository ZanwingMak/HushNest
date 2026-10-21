import AppKit

/// 绘制原创耳机与月牙标志，输出不含透明度的 App Store 图标。
func generateIcon(at path: String) throws {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
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
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

try generateIcon(at: CommandLine.arguments[1])
