import AppKit

let options = LaunchOptions(CommandLine.arguments)
if let command = options.popupScreenCommand {
    func rect(_ text: String) -> NSRect {
        let v = text.split(separator: ",").compactMap { Double($0) }
        return v.count == 4 ? NSRect(x: v[0], y: v[1], width: v[2], height: v[3]) : .zero
    }
    let screens = command[1].split(separator: ";").map { rect(String($0)) }
    Console.line(PopupScreen.index(widget: rect(command[0]), screens: screens).map(String.init) ?? "none")
    exit(0)
}
if options.printHotKey {
    Console.line("\(NewSessionHotKey.label) keyCode=\(NewSessionHotKey.keyCode) modifiers=\(NewSessionHotKey.modifiers)")
    exit(0)
}
if let id = options.resumeURLId {
    Console.line(NewSessionLauncher.resumeURL(sessionId: id)?.absoluteString ?? "nil")
    exit(0)
}
let source: SessionSource = options.useSample ? .sample : .live

if let command = options.newSessionCommand {
    let request = NewSessionRequest(folder: command.folder == "none" ? nil : command.folder, prompt: command.prompt, target: command.target)
    do { try NewSessionLauncher.validate(request) } catch {
        Console.line("error: \(error.localizedDescription)")
        exit(1)
    }
    if command.action == "--print-new-session" {
        switch request.target {
        case .desktop: Console.line(NewSessionLauncher.desktopURL(for: request)?.absoluteString ?? "nil")
        case .terminal: Console.line(NewSessionLauncher.terminalScript(for: request))
        case .background, .backgroundDesktop: Console.line(NewSessionLauncher.backgroundScript(for: request))
        }
        exit(0)
    }
    var finished = false
    var failed = false
    NewSessionLauncher.start(request) { result in
        switch result {
        case .success(let text): Console.line(text)
        case .failure(let error):
            Console.line("error: \(error.localizedDescription)")
            failed = true
        }
        finished = true
    }
    while !finished { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1)) }
    exit(failed ? 1 : 0)
}

if let command = options.updateCommand {
    switch command[0] {
    case "--test-version-compare":
        for (candidate, installed) in [("1.2.1", "1.2.0"), ("1.10.0", "1.9.9"), ("v2.0", "1.99"), ("1.2.0", "1.2.0"), ("1.1.9", "1.2.0"), ("1.2", "1.2.0")] {
            Console.line("\(candidate) > \(installed): \(AppVersion.isNewer(candidate, than: installed))")
        }
    case "--check-update":
        do {
            let release = try UpdateService.fetchLatest()
            Console.line(AppVersion.isNewer(release.version, than: AppVersion.current) ? "update available \(release.version)" : "up to date \(AppVersion.current)")
        } catch {
            Console.line("could not check: \(error.localizedDescription)")
            exit(1)
        }
    case "--download-update":
        guard command.count > 1 else { exit(1) }
        do {
            let app = try UpdateService.download(try UpdateService.fetchLatest(), into: URL(fileURLWithPath: command[1]))
            Console.line("downloaded \(app.path)")
        } catch {
            Console.line("failed: \(error.localizedDescription)")
            exit(1)
        }
    default:
        guard command.count > 3, let pid = Int32(command[1]) else { exit(1) }
        Console.line(UpdateService.script(waitingFor: pid, newApp: URL(fileURLWithPath: command[2]), destination: URL(fileURLWithPath: command[3])))
    }
    exit(0)
}

if let choice = options.answerOption {
    guard let request = PermissionRequests.load().first(where: { $0.id == choice.requestId }), request.questions.count == 1,
          request.questions[0].options.indices.contains(choice.index)
    else {
        Console.line("no such question or option")
        exit(1)
    }
    let question = request.questions[0]
    PermissionRequests.answer(request, answers: [question.question: question.options[choice.index].label])
    Console.line("answered \(question.options[choice.index].label)")
    exit(0)
}

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

if let hookCommand = options.hookCommand {
    do {
        switch hookCommand {
        case "--install-hook": try HookInstaller.install()
        case "--uninstall-hook": try HookInstaller.uninstall()
        default: break
        }
        Console.line("hook installed=\(HookInstaller.isInstalled())")
    } catch {
        Console.line("failed: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

if options.testTerminal {
    Console.line(SessionJumper.terminalScript(cwd: "/work/it's here", sessionId: "11111111-2222-3333-4444-555555555555") ?? "nil")
    Console.line(SessionJumper.terminalScript(cwd: "relative", sessionId: "11111111-2222-3333-4444-555555555555") ?? "nil")
    Console.line(SessionJumper.terminalScript(cwd: "/work", sessionId: "bad id; rm -rf /") ?? "nil")
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
