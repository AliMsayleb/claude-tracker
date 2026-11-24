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
    let openShortcuts: Bool
    let printShortcuts: Bool
    let testCursors: Bool
    let testWidgetDrag: Bool
    let testSearch: Bool
    let testWidgetSize: Bool
    let testPopup: Bool
    let testReturnKey: Bool
    let timeDetailPid: Int32?
    let detailPid: Int32?
    let send: (pid: Int32, text: String)?
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
        openShortcuts = arguments.contains("--open-shortcuts")
        printShortcuts = arguments.contains("--print-shortcuts")
        testCursors = arguments.contains("--test-cursors")
        testWidgetDrag = arguments.contains("--test-widget-drag")
        testSearch = arguments.contains("--test-search")
        testWidgetSize = arguments.contains("--test-widget-size")
        testPopup = arguments.contains("--test-popup")
        testReturnKey = arguments.contains("--test-return-key")
        timeDetailPid = Self.values(after: "--time-detail", count: 1, in: arguments).flatMap { Int32($0[0]) }
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
