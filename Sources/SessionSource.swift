import Foundation

struct SessionSource {
    let prepare: () -> Void
    let housekeeping: () -> Void
    let load: () -> [SessionRow]
    let jump: (SessionRow) -> Void
    let openTerminal: (SessionRow) -> Void
    let decide: (PermissionRequest, PermissionDecision) -> Void
    let answer: (PermissionRequest, [String: String]) -> Void
    let remove: (SessionRow) -> Void
    let add: (DesktopSession) -> Void
    let candidates: () -> [DesktopSession]
    let detail: (SessionRow) -> String?
    let markSeen: (SessionRow) -> Void
    let markUnread: (SessionRow) -> Void
    let send: (SessionRow, String) throws -> Void
    let startSession: (NewSessionRequest, @escaping (Result<String, NewSessionError>) -> Void) -> Void
    let handOff: (String) -> Void
    let shutdown: () -> Void
}

extension SessionSource {
    static let live = SessionSource(
        prepare: PermissionRequests.installHookScript,
        housekeeping: LiveSessions.housekeeping,
        load: LiveSessions.rows,
        jump: SessionJumper.jump,
        openTerminal: SessionJumper.openInTerminal,
        decide: PermissionRequests.decide,
        answer: PermissionRequests.answer,
        remove: LiveSessions.remove,
        add: LiveSessions.add,
        candidates: LiveSessions.candidates,
        detail: SessionDetail.lastAssistantText,
        markSeen: LiveSessions.markSeen,
        markUnread: LiveSessions.markUnread,
        send: { try SessionMessenger.send($1, to: $0) },
        startSession: NewSessionLauncher.start,
        handOff: HandOffCenter.handOff,
        shutdown: PermissionRequests.stopBeating
    )

    static let sample = SessionSource(
        prepare: {},
        housekeeping: {},
        load: { SampleData.rows },
        jump: { Console.line("jump pid=\($0.pid)") },
        openTerminal: { Console.line("terminal pid=\($0.pid)") },
        decide: { Console.line("decide \($0.id) \($1.rawValue)") },
        answer: { Console.line("answer \($0.id) \($1.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";"))") },
        remove: { Console.line("remove pid=\($0.pid)") },
        add: { Console.line("add \($0.id)") },
        candidates: {
            ["Older session", "Fix onboarding crash", "Plan Q1 roadmap", "Investigate slow query"].enumerated().map { index, title in
                DesktopSession(id: "local_sample\(index)", title: title, folder: "backend", lastActivity: Date(timeIntervalSinceNow: -Double(index + 1) * 3600),
                               isUnread: false, summary: nil, cliSessionId: nil, cwd: nil)
            }
        },
        detail: { _ in "## Done\nI **refactored** 3 screens and ran `swift test`.\n- First item with *emphasis*\n- Second item\n1. Numbered step\n```\nlet answer = 42\n```" },
        markSeen: { Console.line("seen pid=\($0.pid)") },
        markUnread: { Console.line("unread pid=\($0.pid)") },
        send: { Console.line("send pid=\($0.pid) \($1)") },
        startSession: { request, completion in
            do { try NewSessionLauncher.validate(request) } catch {
                completion(.failure(error as? NewSessionError ?? .launchFailed(error.localizedDescription)))
                return
            }
            Console.line("start \(request.target.rawValue) \(request.folder ?? "none") \(request.prompt.replacingOccurrences(of: "\n", with: "\\n"))")
            completion(.success("started"))
        },
        handOff: { Console.line("handoff \($0)") },
        shutdown: {}
    )
}

enum LiveSessions {
    static func rows() -> [SessionRow] {
        let state = WidgetStateStore.load()
        let requests = PermissionRequests.load()
        let desktop = DesktopSessions.all(seen: state.seen, unreadMarks: state.unreadMarks)
        let desktopById = Dictionary(desktop.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let running = SessionRegistry.loadRecords()
            .map { record in
                let own = requests.filter { $0.sessionId == record.sessionId }
                var row = SessionRegistry.makeRow(record, requests: own, desktop: record.hostSessionId.flatMap { desktopById[$0] })
                row.agents = SessionDetail.agentProgress(of: row)
                return row
            }
            .filter { !state.hidden.contains($0.key) }
        let runningKeys = Set(running.map(\.key))
        let pinned = desktop
            .filter { state.pinned.contains($0.id) && !runningKeys.contains($0.id) }
            .map(notRunningRow)
        return (running + pinned).sorted(by: SessionRegistry.isListedBefore)
    }

    static func remove(_ row: SessionRow) {
        WidgetStateStore.update {
            $0.hidden.insert(row.key)
            $0.pinned.removeAll { $0 == row.key }
        }
    }

    static func markSeen(_ row: SessionRow) {
        guard let host = row.hostSessionId else { return }
        WidgetStateStore.update { $0.seen[host] = Date().timeIntervalSince1970 * 1000 }
    }

    static func markUnread(_ row: SessionRow) {
        guard let host = row.hostSessionId else { return }
        WidgetStateStore.update { $0.unreadMarks[host] = Date().timeIntervalSince1970 * 1000 }
    }

    static func add(_ session: DesktopSession) {
        WidgetStateStore.update {
            $0.hidden.remove(session.id)
            if !$0.pinned.contains(session.id) { $0.pinned.append(session.id) }
        }
    }

    static func candidates() -> [DesktopSession] {
        let shown = Set(rows().map(\.key))
        return DesktopSessions.all()
            .filter { !shown.contains($0.id) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    private static func notRunningRow(_ session: DesktopSession) -> SessionRow {
        let hash = session.id.utf8.reduce(5381) { ($0 &* 33 &+ Int($1)) & 0x3fffffff }
        return SessionRow(
            pid: Int32(-hash - 1), sessionId: session.cliSessionId, title: session.title, folder: session.folder, state: .idle,
            since: session.lastActivity, origin: .desktop, hostSessionId: session.id, running: false,
            summary: session.summary, cwd: session.cwd
        )
    }

    static func housekeeping() {
        PermissionRequests.beat()
        PermissionRequests.discardStale(PermissionRequests.load(), sessions: SessionRegistry.loadRecords())
    }
}

enum SampleData {
    static var rows: [SessionRow] {
        let now = Date()
        let question = PermissionRequest(
            id: "sample-question", sessionId: "sample-2", toolName: "AskUserQuestion", detail: "", createdAt: now - 420,
            questions: [AskQuestion(
                question: "Which environment should I deploy to?", header: "Deploy", multiSelect: false,
                options: [
                    AskOption(label: "Staging", description: "Safe to test first"),
                    AskOption(label: "Production", description: "Goes live to users"),
                    AskOption(label: "Cancel", description: "Do not deploy"),
                ]
            )]
        )
        let command = PermissionRequest(
            id: "sample-request",
            sessionId: "sample-1",
            toolName: "Bash",
            detail: "npm run reconcile -- --since 2026-11-01 --apply --notify finance@example.com",
            createdAt: now - 140
        )
        let samples = [
            sample(1, "Fix reconciliation report", "backend", .needsPermission, now - 140, [command]),
            sample(2, "Review payments PR", "mobile-app", .needsInput, now - 420, [question]),
            sample(3, "Migrate trade updates", "backend", .working, now - 30, agents: AgentProgress(done: 4, total: 6)),
            sample(4, "Claude Code sessions floating widget", "No folder", .working, now - 5),
            sample(5, "Refactor onboarding screens", "mobile-app", .unread, now - 1500,
                   summary: "Refactored 3 screens; tests pass"),
            sample(6, "Write release notes", "docs", .idle, now - 7200, ready: HandOffPreview.enabled),
        ]
        return samples.sorted(by: SessionRegistry.isListedBefore)
    }

    private static func sample(
        _ number: Int32, _ title: String, _ folder: String, _ state: SessionState, _ since: Date,
        _ requests: [PermissionRequest] = [], summary: String? = nil, agents: AgentProgress? = nil, ready: Bool = false
    ) -> SessionRow {
        SessionRow(
            pid: number, sessionId: "sample-\(number)", title: title, folder: folder, state: state,
            since: since, origin: .desktop, hostSessionId: "local_sample-\(number)", requests: requests, summary: summary, cwd: nil, agents: agents, readyForDesktop: ready
        )
    }
}
