import AppKit

enum ResizeEdge {
    case left
    case right
    case bottom
}

enum WidgetResize {
    static let minWidth: CGFloat = 260
    static let maxWidth: CGFloat = 800
    static let minHeight: CGFloat = 80

    static func frame(from start: NSRect, edge: ResizeEdge, dx: CGFloat, dy: CGFloat) -> NSRect {
        switch edge {
        case .left:
            let width = clamp(start.width - dx)
            return NSRect(x: start.maxX - width, y: start.minY, width: width, height: start.height)
        case .right:
            return NSRect(x: start.minX, y: start.minY, width: clamp(start.width + dx), height: start.height)
        case .bottom:
            let height = max(minHeight, start.height - dy)
            return NSRect(x: start.minX, y: start.maxY - height, width: start.width, height: height)
        }
    }

    private static func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }
}

final class WidgetResizer {
    static var mouseLocation: () -> NSPoint = { NSEvent.mouseLocation }

    weak var window: NSWindow?
    var onEnd: () -> Void = {}

    private var startFrame: NSRect?
    private var startMouse: NSPoint?

    var isResizing: Bool { startFrame != nil }

    func drag(_ edge: ResizeEdge) {
        guard let window else { return }
        let mouse = Self.mouseLocation()
        if startFrame == nil {
            startFrame = window.frame
            startMouse = mouse
        }
        guard let start = startFrame, let origin = startMouse else { return }
        window.setFrame(WidgetResize.frame(from: start, edge: edge, dx: mouse.x - origin.x, dy: mouse.y - origin.y), display: true)
    }

    func end() {
        guard isResizing else { return }
        startFrame = nil
        startMouse = nil
        onEnd()
    }
}
