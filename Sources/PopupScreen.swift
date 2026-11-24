import AppKit

enum PopupScreen {
    static func index(widget: NSRect, screens: [NSRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let center = NSPoint(x: widget.midX, y: widget.midY)
        if let inside = screens.firstIndex(where: { $0.contains(center) }) { return inside }
        func overlap(_ screen: NSRect) -> CGFloat {
            let shared = screen.intersection(widget)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        return screens.indices.max { overlap(screens[$0]) < overlap(screens[$1]) }
    }

    static func centeredOrigin(size: NSSize, in area: NSRect, lift: CGFloat = 0) -> NSPoint {
        NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2 + area.height * lift)
    }
}
