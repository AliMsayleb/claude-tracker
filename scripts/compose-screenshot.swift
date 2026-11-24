import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let source = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: compose-screenshot <input.png> <output.png>\n".utf8))
    exit(1)
}
let padding: CGFloat = 90
let scale: CGFloat = 2
let width = source.size.width + padding * 2
let height = source.size.height + padding * 2
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
bitmap.size = NSSize(width: width, height: height)
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let backdrop = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height), xRadius: 36, yRadius: 36)
NSGradient(
    starting: NSColor(red: 0.96, green: 0.88, blue: 0.82, alpha: 1),
    ending: NSColor(red: 0.85, green: 0.62, blue: 0.52, alpha: 1)
)?.draw(in: backdrop, angle: -60)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
source.draw(in: NSRect(x: padding, y: padding, width: source.size.width, height: source.size.height))
NSGraphicsContext.restoreGraphicsState()
try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[2]))
