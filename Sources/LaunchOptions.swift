import CoreGraphics

struct LaunchOptions {
    struct Decision {
        let requestId: String
        let decision: PermissionDecision
    }

    let useSample: Bool
    let dump: Bool
    let collectGarbage: Bool
    let testDoubleTap: Bool
    let snapshotPath: String?
    let clickPoint: CGPoint?
    let commandClick: Bool
    let previewHover: String?
    let testSelectAll: Bool
    let testMarkdown: Bool
    let testTyping: Bool
    let testResize: Bool
    let previewAllHover: Bool
    let testKeyboardIsolation: Bool
    let openNewSession: Bool
    let newSessionSize: (width: Double, height: Double)?
    let noFolder: Bool
    let draft: (folder: String, prompt: String)?
    let startTarget: NewSessionTarget?
    let resumeURLId: String?
    let popupScreenCommand: [String]?
    let testHotKey: Bool
    let printHotKey: Bool
    let newSessionCommand: (action: String, target: NewSessionTarget, folder: String, prompt: String)?
    let startCollapsed: Bool
    let updateCommand: [String]?
    let hookCommand: String?
    let previewRowHover: Bool
    let testTerminal: Bool
    let openShortcuts: Bool
    let printShortcuts: Bool
    let testCursors: Bool
    let testWidgetDrag: Bool
    let testSearch: Bool
    let testWidgetSize: Bool
    let midDragHeight: Double?
    let widgetCap: Double?
    let testPopup: Bool
    let testReturnKey: Bool
    let timeDetailPid: Int32?
    let detailPid: Int32?
    let send: (pid: Int32, text: String)?
    let answerOption: (requestId: String, index: Int)?
    let decision: Decision?

    init(_ arguments: [String]) {
        useSample = arguments.contains("--sample")
        dump = arguments.contains("--dump")
        collectGarbage = arguments.contains("--gc")
        testDoubleTap = arguments.contains("--test-double-tap")
        snapshotPath = Self.values(after: "--snapshot", count: 1, in: arguments)?.first
        commandClick = arguments.contains("--command-click")
        previewHover = Self.values(after: "--preview-hover", count: 1, in: arguments)?.first
        testSelectAll = arguments.contains("--test-select-all")
        testMarkdown = arguments.contains("--test-markdown")
        testTyping = arguments.contains("--test-typing")
        testResize = arguments.contains("--test-resize")
        previewAllHover = arguments.contains("--preview-all-hover")
        testKeyboardIsolation = arguments.contains("--test-keyboard-isolation")
        openNewSession = arguments.contains("--open-new-session")
        newSessionSize = Self.values(after: "--new-session-size", count: 2, in: arguments).flatMap { values in
            Double(values[0]).flatMap { width in Double(values[1]).map { (width, $0) } }
        }
        noFolder = arguments.contains("--new-session-no-folder")
        HandOffPreview.enabled = arguments.contains("--preview-handoff")
        draft = Self.values(after: "--draft-new-session", count: 2, in: arguments).map { ($0[0], $0[1]) }
        startTarget = Self.values(after: "--start-new-session", count: 1, in: arguments).flatMap { NewSessionTarget(rawValue: $0[0]) }
        newSessionCommand = ["--print-new-session", "--start-session"].compactMap { flag in
            Self.values(after: flag, count: 3, in: arguments).flatMap { values in
                NewSessionTarget(rawValue: values[0]).map { (flag, $0, values[1], values[2]) }
            }
        }.first
        popupScreenCommand = Self.values(after: "--print-popup-screen", count: 2, in: arguments)
        testHotKey = arguments.contains("--test-hotkey")
        printHotKey = arguments.contains("--print-hotkey")
        resumeURLId = Self.values(after: "--print-resume-url", count: 1, in: arguments)?.first
        startCollapsed = arguments.contains("--start-collapsed")
        updateCommand = arguments.firstIndex { ["--check-update", "--download-update", "--print-update-script", "--test-version-compare"].contains($0) }
            .map { Array(arguments[$0...]) }
        hookCommand = ["--install-hook", "--uninstall-hook", "--hook-status"].first { arguments.contains($0) }
        previewRowHover = arguments.contains("--preview-row-hover")
        testTerminal = arguments.contains("--test-terminal-script")
        openShortcuts = arguments.contains("--open-shortcuts")
        printShortcuts = arguments.contains("--print-shortcuts")
        testCursors = arguments.contains("--test-cursors")
        testWidgetDrag = arguments.contains("--test-widget-drag")
        testSearch = arguments.contains("--test-search")
        testWidgetSize = arguments.contains("--test-widget-size")
        widgetCap = Self.values(after: "--widget-cap", count: 1, in: arguments).flatMap { Double($0[0]) }
        midDragHeight = Self.values(after: "--test-mid-drag", count: 1, in: arguments).flatMap { Double($0[0]) }
        testPopup = arguments.contains("--test-popup")
        testReturnKey = arguments.contains("--test-return-key")
        timeDetailPid = Self.values(after: "--time-detail", count: 1, in: arguments).flatMap { Int32($0[0]) }
        answerOption = Self.values(after: "--answer", count: 2, in: arguments).flatMap { values in Int(values[1]).map { (values[0], $0) } }
        send = Self.values(after: "--send", count: 2, in: arguments).flatMap { values in Int32(values[0]).map { ($0, values[1]) } }
        detailPid = Self.values(after: "--detail", count: 1, in: arguments).flatMap { Int32($0[0]) }
        clickPoint = Self.values(after: arguments.contains("--command-click") ? "--command-click" : "--click", count: 2, in: arguments)
            .flatMap { values in
                guard let x = Double(values[0]), let y = Double(values[1]) else { return nil }
                return CGPoint(x: x, y: y)
            }
        decision = Self.values(after: "--decide", count: 2, in: arguments)
            .flatMap { values in
                guard let decision = PermissionDecision(rawValue: values[1]) else { return nil }
                return Decision(requestId: values[0], decision: decision)
            }
    }

    private static func values(after flag: String, count: Int, in arguments: [String]) -> [String]? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + count else { return nil }
        return Array(arguments[(index + 1)...(index + count)])
    }
}
