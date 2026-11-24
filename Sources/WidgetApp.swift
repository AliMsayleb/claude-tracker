import AppKit
import Combine
import SwiftUI

enum TestInput {
    static var ignoresRealKeyboard = false
    static var sendingScriptedKeys = false

    static func shouldDrop(_ event: NSEvent) -> Bool {
        ignoresRealKeyboard && !sendingScriptedKeys && [.keyDown, .keyUp, .flagsChanged].contains(event.type)
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if TestInput.shouldDrop(event) { return }
        super.sendEvent(event)
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ReplyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if TestInput.shouldDrop(event) { return }
        super.sendEvent(event)
    }

    var onClose: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift)
        guard modifiers == .command else { return super.performKeyEquivalent(with: event) }
        let key = event.charactersIgnoringModifiers
        switch key {
        case "+", "=": ReplyZoom.shared.zoomIn(); return true
        case "-": ReplyZoom.shared.zoomOut(); return true
        case "0": ReplyZoom.shared.reset(); return true
        case "w": onClose?(); return true
        default: break
        }
        if event.modifierFlags.contains(.shift) { return super.performKeyEquivalent(with: event) }
        if let action = Self.editAction(for: key), firstResponder?.tryToPerform(action, with: self) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    private static func editAction(for key: String?) -> Selector? {
        switch key {
        case "a": return #selector(NSText.selectAll(_:))
        case "c": return #selector(NSText.copy(_:))
        case "x": return #selector(NSText.cut(_:))
        case "v": return #selector(NSText.paste(_:))
        case "z": return Selector(("undo:"))
        default: return nil
        }
    }
}

final class FittingHostingView<Content: View>: NSHostingView<Content> {
    var onContentSizeChange: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onContentSizeChange?() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let frameName = "ClaudeSessionsWidget"
    private static let replySizeKey = "replyPopupSize"
    private static let widgetMaxHeightKey = "widgetMaxHeight"

    private let store: SessionStore
    private let options: LaunchOptions
    private var panel: FloatingPanel!
    private var hostingView: FittingHostingView<WidgetView>!
    private var storeObserver: AnyCancellable?
    private var replyObserver: AnyCancellable?
    private var replyPanel: ReplyPanel!
    private var resizeObserver: NSObjectProtocol?
    private var pickerPanel: KeyablePanel!
    private var shortcutsPanel: KeyablePanel!
    private var newSessionPanel: KeyablePanel!
    private var newSessionObserver: AnyCancellable?
    private var shortcutsObserver: AnyCancellable?
    private var shortcutsResignObserver: NSObjectProtocol?
    private var pickerObserver: AnyCancellable?
    private var pickerResignObserver: NSObjectProtocol?
    private var lastFittedHeight: CGFloat = 0
    private let resizer = WidgetResizer()
    private lazy var updates: UpdateController? = options.useSample ? nil : UpdateController(store: store)
    private var savedDefaults: [String: Any] = [:]
    private static let sandboxedKeys = ["replyPopupSize", "replyFontScale", "widgetMaxHeight", "collapsed", "openTarget", "newSessionTarget", "newSessionSize"]
    private static let newSessionSizeKey = "newSessionSize"
    private var isApplyingNewSessionSize = false
    private var newSessionResizeObserver: Any?
    private var isApplyingReplySize = false
    private var replyHostingView: NSHostingView<ReplyView>!
    private var doubleCommandTap: DoubleCommandTap?
    private var newSessionHotKey: NewSessionHotKey?

    init(store: SessionStore, options: LaunchOptions) {
        self.store = store
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if options.useSample {
            for key in Self.sandboxedKeys { savedDefaults[key] = UserDefaults.standard.object(forKey: key) }
            for key in ["replyPopupSize", "replyFontScale", "widgetMaxHeight", "collapsed", "newSessionTarget", "newSessionSize"] { UserDefaults.standard.removeObject(forKey: key) }
            store.newSession.forgetSavedChoices()
            if options.startCollapsed { UserDefaults.standard.set(true, forKey: "collapsed") }
            UserDefaults.standard.set(900.0, forKey: Self.widgetMaxHeightKey)
        }
        TestInput.ignoresRealKeyboard = options.useSample
        if options.useSample { ClickModifiers.current = { [options] in options.commandClick ? .command : [] } }
        HoverPreview.symbol = options.previewHover
        RowHoverPreview.enabled = options.previewRowHover || options.previewAllHover
        HoverPreview.forceAll = options.previewAllHover
        installMainMenu()
        let backgroundCursorEnabled = BackgroundCursor.enable()
        if options.testCursors { Console.line("background cursor enabled=\(backgroundCursorEnabled)") }
        if options.testWidgetSize { UserDefaults.standard.set(220.0, forKey: Self.widgetMaxHeightKey) }
        hostingView = FittingHostingView(rootView: WidgetView(store: store, resizer: resizer, updates: updates, onQuit: { NSApp.terminate(nil) }))
        hostingView.onContentSizeChange = { [weak self] in self?.fitPanelToContent() }

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: WidgetMetrics.width, height: hostingView.fittingSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        resizer.window = panel
        resizer.onEnd = { [weak self] in self?.rememberWidgetHeight() }
        panel.contentView = hostingView
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        storeObserver = store.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.fitPanelToContent() } }

        replyHostingView = NSHostingView(rootView: ReplyView(store: store, onClose: { [weak self] in self?.store.closeReply() }))
        replyPanel = ReplyPanel(
            contentRect: NSRect(x: 0, y: 0, width: ReplyMetrics.width, height: ReplyMetrics.height),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        replyPanel.contentView = replyHostingView
        replyPanel.level = .normal
        replyPanel.hidesOnDeactivate = false
        replyPanel.onClose = { [weak self] in self?.store.closeReply() }
        replyPanel.isOpaque = false
        replyPanel.backgroundColor = .clear
        replyPanel.hasShadow = true
        replyPanel.isMovableByWindowBackground = true
        replyPanel.minSize = NSSize(width: ReplyMetrics.minWidth, height: ReplyMetrics.minHeight)
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: replyPanel, queue: .main
        ) { [weak self] _ in self?.rememberReplySize() }
        pickerPanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: PickerMetrics.width, height: PickerMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        pickerPanel.contentView = NSHostingView(rootView: AddSessionView(store: store, onClose: { [weak self] in self?.store.closePicker() }))
        pickerPanel.level = .floating
        pickerPanel.isOpaque = false
        pickerPanel.backgroundColor = .clear
        pickerPanel.hasShadow = true
        pickerPanel.hidesOnDeactivate = false
        shortcutsPanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: ShortcutsMetrics.width, height: ShortcutsMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        shortcutsPanel.contentView = NSHostingView(rootView: ShortcutsView(onClose: { [weak self] in self?.store.closeShortcuts() }))
        shortcutsPanel.level = .floating
        shortcutsPanel.isOpaque = false
        shortcutsPanel.backgroundColor = .clear
        shortcutsPanel.hasShadow = true
        shortcutsPanel.hidesOnDeactivate = false
        newSessionPanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: NewSessionMetrics.width, height: NewSessionMetrics.height),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newSessionPanel.contentView = NSHostingView(rootView: NewSessionView(model: store.newSession, onClose: { [weak self] in self?.store.closeNewSession() }))
        newSessionPanel.level = .floating
        newSessionPanel.isOpaque = false
        newSessionPanel.backgroundColor = .clear
        newSessionPanel.hasShadow = true
        newSessionPanel.hidesOnDeactivate = false
        newSessionPanel.isMovableByWindowBackground = true
        newSessionPanel.minSize = NSSize(width: NewSessionMetrics.minWidth, height: NewSessionMetrics.minHeight)
        newSessionResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: newSessionPanel, queue: .main
        ) { [weak self] _ in self?.rememberNewSessionSize() }
        newSessionObserver = store.$newSessionOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] open in self?.showNewSession(open) }
        shortcutsObserver = store.$shortcutsOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] open in self?.showShortcuts(open) }
        pickerObserver = store.$pickerOpen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] open in self?.showPicker(open) }
        replyObserver = store.$replyKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in self?.showReplyPanel(visible: key != nil) }

        placePanel()
        panel.orderFrontRegardless()
        store.start()
        scheduleTestHooks()
        if !options.useSample, !UserDefaults.standard.bool(forKey: "shownShortcutsIntro") {
            UserDefaults.standard.set(true, forKey: "shownShortcutsIntro")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.store.openShortcuts() }
        }
        updates?.startAutomaticChecks()
        if !options.useSample {
            doubleCommandTap = DoubleCommandTap { [weak self] in self?.toggleVisibility() }
            doubleCommandTap?.start(promptForPermission: true)
            newSessionHotKey = NewSessionHotKey { [weak self] in self?.toggleNewSessionFromHotKey() }
            newSessionHotKey?.register()
        }
        if options.testHotKey {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                Console.line("hotkey registered=\(self?.newSessionHotKey != nil)")
                NSApp.terminate(nil)
            }
        }
    }

    private func showReplyPanel(visible: Bool) {
        guard visible else {
            hideReplyPanel()
            return
        }
        if !options.useSample { NSApp.setActivationPolicy(.regular) }
        if !replyPanel.isVisible {
            applySavedReplySize()
            if let area = popupArea {
                replyPanel.setFrameOrigin(parked(PopupScreen.centeredOrigin(size: replyPanel.frame.size, in: area, lift: 0.05)))
            }
            replyPanel.alphaValue = 0
        }
        replyPanel.makeKeyAndOrderFront(nil)
        if !options.useSample { NSApp.activate(ignoringOtherApps: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            replyPanel.animator().alphaValue = 1
        }
    }

    private func hideReplyPanel() {
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            context.duration = 0.12
            self?.replyPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.store.replyKey == nil else { return }
            self.replyPanel.orderOut(nil)
            if !self.options.useSample { NSApp.setActivationPolicy(.accessory) }
        })
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if store.replyKey != nil { replyPanel.makeKeyAndOrderFront(nil) }
    }

    private func applySavedNewSessionSize() {
        let stored = UserDefaults.standard.array(forKey: Self.newSessionSizeKey) as? [Double]
        let saved = stored.flatMap { $0.count == 2 ? NSSize(width: $0[0], height: $0[1]) : nil }
            ?? NSSize(width: NewSessionMetrics.width, height: NewSessionMetrics.height)
        let limit = popupArea?.size ?? saved
        isApplyingNewSessionSize = true
        newSessionPanel.setContentSize(NSSize(
            width: min(max(saved.width, NewSessionMetrics.minWidth), limit.width),
            height: min(max(saved.height, NewSessionMetrics.minHeight), limit.height)
        ))
        isApplyingNewSessionSize = false
    }

    private func rememberNewSessionSize() {
        guard !isApplyingNewSessionSize, newSessionPanel.isVisible else { return }
        let size = newSessionPanel.contentRect(forFrameRect: newSessionPanel.frame).size
        UserDefaults.standard.set([Double(size.width), Double(size.height)], forKey: Self.newSessionSizeKey)
    }

    private func applySavedReplySize() {
        let stored = UserDefaults.standard.array(forKey: Self.replySizeKey) as? [Double]
        let saved = stored.flatMap { $0.count == 2 ? NSSize(width: $0[0], height: $0[1]) : nil }
            ?? NSSize(width: ReplyMetrics.width, height: ReplyMetrics.height)
        let limit = popupArea?.size ?? saved
        isApplyingReplySize = true
        replyPanel.setContentSize(NSSize(
            width: min(max(saved.width, ReplyMetrics.minWidth), limit.width),
            height: min(max(saved.height, ReplyMetrics.minHeight), limit.height)
        ))
        isApplyingReplySize = false
    }

    private func rememberReplySize() {
        guard !isApplyingReplySize, replyPanel.isVisible else { return }
        let size = replyPanel.contentRect(forFrameRect: replyPanel.frame).size
        UserDefaults.standard.set([Double(size.width), Double(size.height)], forKey: Self.replySizeKey)
    }

    private func parked(_ origin: NSPoint) -> NSPoint {
        options.useSample ? NSPoint(x: origin.x - 30000, y: origin.y) : origin
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Claude Tracker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        let shortcutsItem = NSMenuItem(title: "Shortcuts & Tips", action: #selector(showShortcutsFromMenu), keyEquivalent: "/")
        shortcutsItem.target = self
        help.addItem(shortcutsItem)
        helpItem.submenu = help
        NSApp.mainMenu = main
    }

    @objc private func showShortcutsFromMenu() {
        store.openShortcuts()
    }

    private var popupArea: NSRect? {
        (panel.screen ?? NSScreen.main)?.visibleFrame
    }

    private func toggleNewSessionFromHotKey() {
        if store.newSessionOpen {
            store.closeNewSession()
            return
        }
        store.openNewSession()
        NSApp.activate(ignoringOtherApps: true)
        newSessionPanel.makeKeyAndOrderFront(nil)
    }

    private func toggleVisibility() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if options.useSample {
            for key in Self.sandboxedKeys {
                if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        store.stop()
    }

    private func placePanel() {
        var restored = false
        if !options.useSample {
            restored = panel.setFrameUsingName(Self.frameName)
            panel.setFrameAutosaveName(Self.frameName)
        }
        fitPanelToContent()
        guard !restored, let screen = NSScreen.main else { return }
        let margin: CGFloat = 16
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(parked(NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)))
    }

    private func fitPanelToContent() {
        guard !resizer.isResizing else { return }
        let height = hostingView.fittingSize.height
        let current = panel.frame
        lastFittedHeight = height
        let fitted = NSRect(x: current.minX, y: current.maxY - height, width: current.width, height: height)
        if fitted != current { panel.setFrame(fitted, display: true) }
    }

    private func rememberWidgetHeight() {
        if abs(panel.frame.height - lastFittedHeight) > 1 {
            UserDefaults.standard.set(Double(panel.frame.height), forKey: Self.widgetMaxHeightKey)
        }
        DispatchQueue.main.async { [weak self] in self?.fitPanelToContent() }
    }

    private func showNewSession(_ open: Bool) {
        guard open else {
            newSessionPanel.orderOut(nil)
            return
        }
        applySavedNewSessionSize()
        if let area = popupArea {
            newSessionPanel.setFrameOrigin(parked(PopupScreen.centeredOrigin(size: newSessionPanel.frame.size, in: area)))
        }
        newSessionPanel.makeKeyAndOrderFront(nil)
    }

    private func showShortcuts(_ open: Bool) {
        if let observer = shortcutsResignObserver {
            NotificationCenter.default.removeObserver(observer)
            shortcutsResignObserver = nil
        }
        guard open else {
            shortcutsPanel.orderOut(nil)
            return
        }
        if let area = popupArea {
            shortcutsPanel.setFrameOrigin(parked(PopupScreen.centeredOrigin(size: NSSize(width: ShortcutsMetrics.width, height: ShortcutsMetrics.height), in: area)))
        }
        shortcutsPanel.makeKeyAndOrderFront(nil)
        guard !options.useSample else { return }
        shortcutsResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: shortcutsPanel, queue: .main
        ) { [weak self] _ in self?.store.closeShortcuts() }
    }

    private func showPicker(_ open: Bool) {
        if let observer = pickerResignObserver {
            NotificationCenter.default.removeObserver(observer)
            pickerResignObserver = nil
        }
        guard open else {
            pickerPanel.orderOut(nil)
            return
        }
        if let area = popupArea {
            pickerPanel.setFrameOrigin(parked(PopupScreen.centeredOrigin(size: NSSize(width: PickerMetrics.width, height: PickerMetrics.height), in: area, lift: 0.05)))
        }
        pickerPanel.makeKeyAndOrderFront(nil)
        guard !options.useSample else { return }
        pickerResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: pickerPanel, queue: .main
        ) { [weak self] _ in self?.store.closePicker() }
    }

    private func scheduleTestHooks() {
        if let point = options.clickPoint {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.click(at: point) }
        }
        if options.testPopup { runPopupTest() }
        if options.testKeyboardIsolation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.store.openNewSession() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.testKeyboardIsolation() }
        }
        if options.testWidgetDrag { runWidgetDragTest() }
        if let draft = options.draft {
            store.newSession.folder = draft.folder
            store.newSession.prompt = draft.prompt
        }
        if options.noFolder { store.newSession.folder = nil }
        if options.previewHandOff { HandOffCenter.shared.markReady("sample-6") }
        if options.openNewSession {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.store.openNewSession() }
        }
        if let size = options.newSessionSize {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.store.openNewSession() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
                self?.newSessionPanel.setContentSize(NSSize(width: size.width, height: size.height))
            }
        }
        if let target = options.startTarget {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.store.newSession.target = target
                self?.store.newSession.start()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { NSApp.terminate(nil) }
        }
        if options.openShortcuts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.store.openShortcuts() }
        }
        if options.testCursors {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.reportCursorAreas() }
        }
        if options.testWidgetSize {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                let frame = self.panel.frame
                self.panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - frame.height, width: 420, height: frame.height), display: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let self else { return }
                Console.line("width=\(Int(self.panel.frame.width)) height<=220=\(self.panel.frame.height <= 221)")
                NSApp.terminate(nil)
            }
        }
        if options.testReturnKey {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.store.openReply(self?.store.rows.first ?? SessionRow.placeholder) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.testReturnKey() }
        }
        if options.testTyping {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.store.openReply(self?.store.rows.first ?? SessionRow.placeholder) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.testTyping() }
        }
        if options.testSelectAll {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.store.openReply(self?.store.rows.first ?? SessionRow.placeholder) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.testSelectAll() }
        }
        if let path = options.snapshotPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.writeSnapshot(to: path) }
        } else if options.clickPoint != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { NSApp.terminate(nil) }
        }
    }

    private func reportCursorAreas() {
        func views(in view: NSView) -> [CursorTrackingView] {
            ((view as? CursorTrackingView).map { [$0] } ?? []) + view.subviews.flatMap(views)
        }
        guard let root = panel.contentView else { return }
        let width = root.bounds.width
        let height = root.bounds.height
        for area in views(in: root).sorted(by: { $0.convert($0.bounds, to: root).minX < $1.convert($1.bounds, to: root).minX }) {
            let frame = area.convert(area.bounds, to: root)
            let options = area.trackingAreas.first?.options ?? []
            let wantsCursorUpdate = options.contains(.cursorUpdate) && options.contains(.mouseEnteredAndExited) && options.contains(.activeAlways)
            NSCursor.arrow.set()
            if let event = NSEvent.enterExitEvent(
                with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
            ) { area.mouseEntered(with: event) }
            let kind = NSCursor.current == NSCursor.resizeLeftRight ? "left-right" : NSCursor.current == NSCursor.resizeUpDown ? "up-down" : "other"
            let place = frame.minX < 1 ? "left edge" : frame.maxX > width - 1 ? "right edge" : frame.minY < 1 || frame.maxY > height - 1 ? "bottom edge" : "elsewhere"
            Console.line("\(place): cursor=\(kind) tracking=\(wantsCursorUpdate) thin=\(min(frame.width, frame.height) <= 9)")
        }
        NSApp.terminate(nil)
    }

    private func runWidgetDragTest() {
        var mouse = NSPoint(x: 1000, y: 500)
        WidgetResizer.mouseLocation = { mouse }
        func send(_ type: NSEvent.EventType, windowPoint: NSPoint, screen: NSPoint) {
            mouse = screen
            let event = NSEvent.mouseEvent(
                with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )
            if let event { panel.sendEvent(event) }
        }
        func drag(at windowPoint: NSPoint, from: NSPoint, to: NSPoint) {
            send(.leftMouseDown, windowPoint: windowPoint, screen: from)
            send(.leftMouseDragged, windowPoint: windowPoint, screen: to)
            send(.leftMouseUp, windowPoint: windowPoint, screen: to)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            let first = panel.frame
            drag(at: NSPoint(x: 3, y: first.height / 2), from: NSPoint(x: 1000, y: 500), to: NSPoint(x: 940, y: 500))
            let afterLeft = panel.frame
            Console.line("left edge grew by \(Int(afterLeft.width - first.width)), right edge fixed=\(abs(afterLeft.maxX - first.maxX) < 1)")
            drag(at: NSPoint(x: afterLeft.width - 3, y: afterLeft.height / 2), from: NSPoint(x: 1000, y: 500), to: NSPoint(x: 1040, y: 500))
            let afterRight = panel.frame
            Console.line("right edge grew by \(Int(afterRight.width - afterLeft.width)), left edge fixed=\(abs(afterRight.minX - afterLeft.minX) < 1)")
            drag(at: NSPoint(x: afterRight.width / 2, y: 3), from: NSPoint(x: 1000, y: 500), to: NSPoint(x: 1000, y: 580))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                let afterBottom = panel.frame
                let cap = UserDefaults.standard.double(forKey: Self.widgetMaxHeightKey)
                Console.line("bottom edge shrank by \(Int(afterRight.height - afterBottom.height)), top fixed=\(abs(afterBottom.maxY - afterRight.maxY) < 1), height remembered=\(abs(cap - afterBottom.height) < 2)")
                NSApp.terminate(nil)
            }
        }
    }

    private func testKeyboardIsolation() {
        func scripted(_ character: String) -> NSEvent? {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0
            )
        }
        func system(_ character: String) -> NSEvent? {
            guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: 16, keyDown: true) else { return nil }
            var characters = Array(character.utf16)
            cg.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
            return NSEvent(cgEvent: cg)
        }
        let click = NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        )
        let scriptedKey = scripted("x")
        let realKey = system("y")
        TestInput.sendingScriptedKeys = true
        let scriptedKept = scriptedKey.map { !TestInput.shouldDrop($0) } ?? false
        TestInput.sendingScriptedKeys = false
        Console.line("scripted key kept=\(scriptedKept) "
            + "unscripted key dropped=\(realKey.map { TestInput.shouldDrop($0) } ?? false) "
            + "unscripted synthetic key dropped=\(scriptedKey.map { TestInput.shouldDrop($0) } ?? false) "
            + "mouse kept=\(click.map { !TestInput.shouldDrop($0) } ?? false)")
        NSApp.terminate(nil)
    }

    private func runPopupTest() {
        let row = { [weak self] in self?.store.rows.first ?? SessionRow.placeholder }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.replySizeKey)
        defaults.removeObject(forKey: "replyFontScale")
        ReplyZoom.shared.reset()
        func command(_ character: String, shift: Bool = false) -> NSEvent? {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: replyPanel.windowNumber, context: nil,
                characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0
            )
        }
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        after(1.0) { self.store.openReply(row()) }
        after(1.6) { self.replyPanel.setContentSize(NSSize(width: 900, height: 700)) }
        after(2.0) { self.store.closeReply() }
        after(2.6) { self.store.openReply(row()) }
        after(3.4) {
            let size = self.replyPanel.contentRect(forFrameRect: self.replyPanel.frame).size
            Console.line("reopened size=\(Int(size.width))x\(Int(size.height))")
            self.replyPanel.resignKey()
            Console.line("still open after losing focus=\(self.replyPanel.isVisible && self.store.replyKey != nil)")
            for key in ["=", "=", "+", "-"] { if let event = command(key, shift: key == "+") { _ = self.replyPanel.performKeyEquivalent(with: event) } }
            Console.line("zoom after + + + - = \(ReplyZoom.shared.scale)")
            if let event = command("0") { _ = self.replyPanel.performKeyEquivalent(with: event) }
            Console.line("zoom after reset = \(ReplyZoom.shared.scale)")
            if let event = command("w") { _ = self.replyPanel.performKeyEquivalent(with: event) }
            Console.line("closed by command-W=\(self.store.replyKey == nil)")
            defaults.removeObject(forKey: Self.replySizeKey)
            defaults.removeObject(forKey: "replyFontScale")
            NSApp.terminate(nil)
        }
    }

    private func testReturnKey() {
        guard let editor = replyPanel.firstResponder as? NSTextView else {
            Console.line("no text field focused")
            NSApp.terminate(nil)
            return
        }
        editor.insertText("ab", replacementRange: NSRange(location: 0, length: 0))
        func pressReturn(_ modifiers: NSEvent.ModifierFlags) {
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: replyPanel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                isARepeat: false, keyCode: 36
            )
            TestInput.sendingScriptedKeys = true
            if let event { replyPanel.sendEvent(event) }
            TestInput.sendingScriptedKeys = false
        }
        pressReturn(.shift)
        let afterShift = editor.string.replacingOccurrences(of: "\n", with: "\\n")
        pressReturn([])
        Console.line("after shift-return: [\(afterShift)]")
        NSApp.terminate(nil)
    }

    private func testTyping() {
        guard let editor = replyPanel.firstResponder as? NSTextView else {
            Console.line("no text field focused")
            NSApp.terminate(nil)
            return
        }
        var worst = 0.0
        var slow = 0
        for _ in 0..<300 {
            let start = CACurrentMediaTime()
            editor.insertText("a", replacementRange: editor.selectedRange())
            RunLoop.main.run(until: Date().addingTimeInterval(0.008))
            let overhead = (CACurrentMediaTime() - start) * 1000 - 8
            worst = max(worst, overhead)
            if overhead > 30 { slow += 1 }
        }
        Console.line("typing worst=\(Int(worst))ms slow=\(slow)")
        NSApp.terminate(nil)
    }

    private func testSelectAll() {
        guard let editor = replyPanel.firstResponder as? NSTextView else {
            Console.line("no text field focused")
            NSApp.terminate(nil)
            return
        }
        editor.insertText("hello world", replacementRange: NSRange(location: 0, length: 0))
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: replyPanel.windowNumber,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        )
        let handled = event.map { replyPanel.performKeyEquivalent(with: $0) } ?? false
        Console.line("handled=\(handled) selected=\(editor.selectedRange().length)")
        NSApp.terminate(nil)
    }

    private func click(at point: CGPoint) {
        let location = NSPoint(x: point.x, y: hostingView.bounds.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: options.commandClick ? [.command] : [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )
            if let event { panel.sendEvent(event) }
        }
    }

    private func writeNewSessionSnapshot(to path: String) {
        guard newSessionPanel.isVisible, let view = newSessionPanel.contentView else { return }
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + "-newsession.png"))
        }
    }

    private func writeShortcutsSnapshot(to path: String) {
        guard shortcutsPanel.isVisible, let view = shortcutsPanel.contentView else { return }
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + "-shortcuts.png"))
        }
    }

    private func writePickerSnapshot(to path: String) {
        guard pickerPanel.isVisible, let view = pickerPanel.contentView else { return }
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + "-picker.png"))
        }
    }

    private func writeReplySnapshot(to path: String) {
        guard replyPanel.isVisible else { return }
        let bounds = replyHostingView.bounds
        if let bitmap = replyHostingView.bitmapImageRepForCachingDisplay(in: bounds) {
            replyHostingView.cacheDisplay(in: bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + "-reply.png"))
        }
    }

    private func writeSnapshot(to path: String) {
        writeReplySnapshot(to: path)
        writePickerSnapshot(to: path)
        writeShortcutsSnapshot(to: path)
        writeNewSessionSnapshot(to: path)
        let bounds = hostingView.bounds
        if let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) {
            hostingView.cacheDisplay(in: bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}
