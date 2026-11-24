import AppKit

let options = LaunchOptions(CommandLine.arguments)
let source: SessionSource = options.useSample ? .sample : .live

if let command = options.decision {
    guard let request = PermissionRequests.load().first(where: { $0.id == command.requestId }) else {
        Console.line("no such request: \(command.requestId)")
        exit(1)
    }
    PermissionRequests.decide(request, command.decision)
    exit(0)
}

if options.testDoubleTap {
    let command = NSEvent.ModifierFlags.command
    let scenarios: [(String, [(Bool, NSEvent.ModifierFlags, TimeInterval)])] = [
        ("double", [(false, command, 0), (false, [], 0.05), (false, command, 0.15), (false, [], 0.2)]),
        ("slow", [(false, command, 0), (false, [], 0.05), (false, command, 1.0), (false, [], 1.05)]),
        ("single", [(false, command, 0), (false, [], 0.05)]),
        ("shortcut", [(false, command, 0), (true, command, 0.02), (false, [], 0.05),
                      (false, command, 0.1), (true, command, 0.12), (false, [], 0.15)]),
        ("triple", [(false, command, 0), (false, [], 0.05), (false, command, 0.1), (false, [], 0.15),
                    (false, command, 0.2), (false, [], 0.25)]),
        ("withshift", [(false, command, 0), (false, [command, .shift], 0.02), (false, [], 0.05),
                       (false, command, 0.1), (false, [], 0.15)]),
    ]
    for (name, events) in scenarios {
        var fired = 0
        let tap = DoubleCommandTap { fired += 1 }
        let start = Date()
        for (isKeyDown, modifiers, offset) in events {
            tap.handle(isKeyDown: isKeyDown, modifiers: modifiers, at: start + offset)
        }
        Console.line("\(name)=\(fired)")
    }
    exit(0)
}

if let message = options.send {
    guard let row = source.load().first(where: { $0.pid == message.pid }) else {
        Console.line("no such session")
        exit(1)
    }
    do {
        try source.send(row, message.text)
        Console.line("sent")
    } catch {
        Console.line("failed: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

if options.printShortcuts {
    Console.line(ShortcutCatalog.markdown)
    exit(0)
}

if options.testResize {
    let start = NSRect(x: 100, y: 100, width: 300, height: 400)
    func show(_ name: String, _ frame: NSRect) {
        Console.line("\(name)=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))")
    }
    show("left-wider", WidgetResize.frame(from: start, edge: .left, dx: -50, dy: 0))
    show("right-wider", WidgetResize.frame(from: start, edge: .right, dx: 40, dy: 0))
    show("left-min", WidgetResize.frame(from: start, edge: .left, dx: 500, dy: 0))
    show("right-max", WidgetResize.frame(from: start, edge: .right, dx: 900, dy: 0))
    show("bottom-shorter", WidgetResize.frame(from: start, edge: .bottom, dx: 0, dy: 100))
    show("bottom-taller", WidgetResize.frame(from: start, edge: .bottom, dx: 0, dy: -50))
    show("bottom-min", WidgetResize.frame(from: start, edge: .bottom, dx: 0, dy: 1000))
    exit(0)
}

if options.testSearch {
    func session(_ title: String, _ folder: String) -> DesktopSession {
        DesktopSession(id: title, title: title, folder: folder, lastActivity: Date(), isUnread: false, summary: nil, cliSessionId: nil, cwd: nil)
    }
    let all = [session("Fix reconciliation report", "backend/main"), session("Review payments PR", "mobile-app"), session("Weekly report", "docs/reports")]
    for query in ["", "RECON", "mobile pay", "weekly docs", "xyz", "  "] {
        Console.line("[\(query)]=\(all.filter { $0.matches(query) }.count)")
    }
    exit(0)
}

if options.testMarkdown {
    let text = "# Title\nplain **bold** line\nsecond line\n\n- one\n* two\n3. three\n```\ncode **not bold**\n```\n| a | b |\n| 1 | 2 |"
    for block in MarkdownBlock.parse(text) {
        switch block {
        case .heading(let value, let level): Console.line("heading\(level):\(value)")
        case .paragraph(let value): Console.line("paragraph:\(value.replacingOccurrences(of: "\n", with: "/"))")
        case .bullet(let value, let marker): Console.line("bullet\(marker):\(value)")
        case .code(let value): Console.line("code:\(value.replacingOccurrences(of: "\n", with: "/"))")
        }
    }
    exit(0)
}

if let pid = options.timeDetailPid, let row = source.load().first(where: { $0.pid == pid }) {
    func milliseconds(_ work: () -> Void) -> Int {
        let start = Date()
        work()
        return Int(Date().timeIntervalSince(start) * 1000)
    }
    let first = milliseconds { _ = SessionDetail.lastAssistantText(of: row) }
    let again = milliseconds { _ = SessionDetail.lastAssistantText(of: row) }
    Console.line("first=\(first) again=\(again)")
    exit(0)
}

if let pid = options.detailPid {
    Console.line(source.load().first { $0.pid == pid }.flatMap(SessionDetail.lastAssistantText) ?? "")
    exit(0)
}

if options.collectGarbage {
    source.housekeeping()
    exit(0)
}

if options.dump {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        Console.line(String(decoding: try encoder.encode(source.load()), as: UTF8.self))
    } catch {
        FileHandle.standardError.write(Data("dump failed: \(error)\n".utf8))
        exit(1)
    }
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate(store: SessionStore(source: source), options: options)
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
