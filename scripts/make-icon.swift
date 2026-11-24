import AppKit

let outputDirectory = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

func drawBurst(center: CGPoint, radius: CGFloat, lineWidth: CGFloat) {
    let lengths: [CGFloat] = [1.0, 0.78, 0.95, 0.72, 1.0, 0.8, 0.92, 0.74, 1.0, 0.82, 0.9, 0.76]
    NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1).setStroke()
    for (index, length) in lengths.enumerated() {
        let angle = CGFloat(index) / 12 * 2 * .pi + .pi / 12
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.2, y: center.y + sin(angle) * radius * 0.2))
        path.line(to: CGPoint(x: center.x + cos(angle) * radius * length, y: center.y + sin(angle) * radius * length))
        path.stroke()
    }
}

func png(size: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let s = CGFloat(size)
    let charcoal = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
    let shape = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.06, dy: s * 0.06),
                             xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(starting: NSColor(red: 0.20, green: 0.19, blue: 0.19, alpha: 1), ending: charcoal)?.draw(in: shape, angle: -90)
    drawBurst(center: CGPoint(x: s * 0.5, y: s * 0.52), radius: s * 0.29, lineWidth: s * 0.055)
    let dot = NSRect(x: s * 0.64, y: s * 0.13, width: s * 0.17, height: s * 0.17)
    charcoal.setFill()
    NSBezierPath(ovalIn: dot.insetBy(dx: -s * 0.025, dy: -s * 0.025)).fill()
    NSColor(red: 0.30, green: 0.82, blue: 0.45, alpha: 1).setFill()
    NSBezierPath(ovalIn: dot).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes {
    try? png(size: size)?.write(to: URL(fileURLWithPath: "\(outputDirectory)/\(name).png"))
}
