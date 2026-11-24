import AppKit
import SwiftUI

enum BackgroundCursor {
    @discardableResult
    static func enable() -> Bool {
        typealias MainConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let everything = UnsafeMutableRawPointer(bitPattern: -2)
        guard let mainSymbol = dlsym(everything, "CGSMainConnectionID"),
              let setSymbol = dlsym(everything, "CGSSetConnectionProperty")
        else { return false }
        let connection = unsafeBitCast(mainSymbol, to: MainConnection.self)()
        let set = unsafeBitCast(setSymbol, to: SetProperty.self)
        return set(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }
}

final class CursorTrackingView: NSView {
    let cursor: NSCursor

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        cursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorTrackingView { CursorTrackingView(cursor: cursor) }

    func updateNSView(_ view: CursorTrackingView, context: Context) {}
}
