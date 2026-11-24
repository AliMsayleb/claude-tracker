import AppKit

let coral = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
let outputDirectory = CommandLine.arguments[1]

func squircle(_ s: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.06, dy: s * 0.06),
                 xRadius: s * 0.22, yRadius: s * 0.22)
}

func burst(center: CGPoint, radius: CGFloat, color: NSColor, rays: Int = 12, lineWidth: CGFloat) {
    let lengths: [CGFloat] = [1.0, 0.78, 0.95, 0.72, 1.0, 0.8, 0.92, 0.74, 1.0, 0.82, 0.9, 0.76]
    color.setStroke()
    for index in 0..<rays {
        let angle = CGFloat(index) / CGFloat(rays) * 2 * .pi + .pi / 12
        let length = lengths[index % lengths.count]
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.2, y: center.y + sin(angle) * radius * 0.2))
        path.line(to: CGPoint(x: center.x + cos(angle) * radius * length, y: center.y + sin(angle) * radius * length))
        path.stroke()
    }
}

func render(size: Int, draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

let concepts: [(String, (CGFloat) -> Void)] = [
    ("A-spark", { s in
        let shape = squircle(s)
        NSGradient(starting: NSColor(red: 0.93, green: 0.60, blue: 0.45, alpha: 1),
                   ending: NSColor(red: 0.78, green: 0.38, blue: 0.24, alpha: 1))?.draw(in: shape, angle: -90)
        burst(center: CGPoint(x: s / 2, y: s / 2), radius: s * 0.30, color: NSColor(red: 1, green: 0.95, blue: 0.88, alpha: 1), lineWidth: s * 0.055)
    }),
    ("B-night-spark", { s in
        let shape = squircle(s)
        NSGradient(starting: NSColor(red: 0.20, green: 0.19, blue: 0.19, alpha: 1),
                   ending: NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1))?.draw(in: shape, angle: -90)
        burst(center: CGPoint(x: s * 0.5, y: s * 0.52), radius: s * 0.29, color: coral, lineWidth: s * 0.055)
        let dot = NSRect(x: s * 0.64, y: s * 0.13, width: s * 0.17, height: s * 0.17)
        NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(ovalIn: dot.insetBy(dx: -s * 0.025, dy: -s * 0.025)).fill()
        NSColor(red: 0.30, green: 0.82, blue: 0.45, alpha: 1).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }),
    ("C-sessions", { s in
        let shape = squircle(s)
        NSGradient(starting: NSColor(red: 0.99, green: 0.95, blue: 0.90, alpha: 1),
                   ending: NSColor(red: 0.95, green: 0.86, blue: 0.78, alpha: 1))?.draw(in: shape, angle: -90)
        burst(center: CGPoint(x: s * 0.5, y: s * 0.56), radius: s * 0.25, color: coral, lineWidth: s * 0.05)
        let colors = [NSColor(red: 0.90, green: 0.30, blue: 0.27, alpha: 1), NSColor(red: 0.97, green: 0.62, blue: 0.20, alpha: 1),
                      NSColor(red: 0.30, green: 0.78, blue: 0.42, alpha: 1)]
        for (index, color) in colors.enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: s * (0.33 + CGFloat(index) * 0.15), y: s * 0.17, width: s * 0.09, height: s * 0.09)).fill()
        }
    }),
]

for (name, draw) in concepts {
    try? render(size: 512, draw: draw).representation(using: .png, properties: [:])?
        .write(to: URL(fileURLWithPath: "\(outputDirectory)/\(name).png"))
}

let sheetWidth = 1700, sheetHeight = 620
let sheet = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: sheetWidth, pixelsHigh: sheetHeight, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight).fill()
let labels = ["A  Spark", "B  Night + status dot", "C  Cream + session colors"]
for (index, (name, _)) in concepts.enumerated() {
    let x = 60 + index * 550
    NSImage(contentsOfFile: "\(outputDirectory)/\(name).png")?.draw(in: NSRect(x: x, y: 100, width: 480, height: 480))
    (labels[index] as NSString).draw(at: CGPoint(x: x + 8, y: 40), withAttributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor(white: 0.15, alpha: 1)])
    NSImage(contentsOfFile: "\(outputDirectory)/\(name).png")?.draw(in: NSRect(x: x + 360, y: 20, width: 48, height: 48))
    NSImage(contentsOfFile: "\(outputDirectory)/\(name).png")?.draw(in: NSRect(x: x + 420, y: 28, width: 32, height: 32))
}
NSGraphicsContext.restoreGraphicsState()
try? sheet.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(outputDirectory)/sheet.png"))
