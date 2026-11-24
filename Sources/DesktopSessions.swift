import Foundation

struct DesktopSession: Identifiable, Equatable {
    let id: String
    let title: String
    let folder: String
    let lastActivity: Date
    let isUnread: Bool
    let summary: String?
    let cliSessionId: String?
    let cwd: String?
}

struct WidgetState: Codable, Equatable {
    var hidden: Set<String> = []
    var pinned: [String] = []
    var seen: [String: Double] = [:]
    var unreadMarks: [String: Double] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hidden = try values.decodeIfPresent(Set<String>.self, forKey: .hidden) ?? []
        pinned = try values.decodeIfPresent([String].self, forKey: .pinned) ?? []
        seen = try values.decodeIfPresent([String: Double].self, forKey: .seen) ?? [:]
        unreadMarks = try values.decodeIfPresent([String: Double].self, forKey: .unreadMarks) ?? [:]
    }
}

enum WidgetStateStore {
    private static var file: URL { WidgetPaths.home.appendingPathComponent("state.json") }

    static func load() -> WidgetState {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(WidgetState.self, from: $0) } ?? WidgetState()
    }

    static func update(_ change: (inout WidgetState) -> Void) {
        var state = load()
        change(&state)
        try? FileManager.default.createDirectory(at: WidgetPaths.home, withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: file, options: .atomic)
    }
}

enum DesktopSessions {
    private struct Record: Decodable {
        let sessionId: String
        let title: String?
        let cwd: String?
        let isArchived: Bool?
        let cliSessionId: String?
        let lastActivityAt: Double?
        let lastFocusedAt: Double?
        let lastTurnEdgeAt: Double?
        let postTurnSummary: Summary?
    }

    private struct Summary: Decodable {
        let status_detail: String?
        let needs_action: String?
    }

    private static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_DESKTOP_SESSIONS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    private static var cache: [String: (modified: Date, record: Record)] = [:]
    private static let cacheLock = NSLock()

    private static func record(at file: URL) -> Record? {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[file.path], cached.modified == modified { return cached.record }
        guard let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(Record.self, from: data) else { return nil }
        cache[file.path] = (modified, record)
        return record
    }

    static func isUnread(turnEnded: Double, focused: Double, seen: Double, marked: Double) -> Bool {
        let lastLook = max(focused, seen)
        return turnEnded > lastLook || marked > lastLook
    }

    static func all(seen: [String: Double] = [:], unreadMarks: [String: Double] = [:]) -> [DesktopSession] {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
            .compactMap(record(at:))
            .filter { $0.isArchived != true }
            .map {
                DesktopSession(
                    id: $0.sessionId,
                    title: $0.title ?? "Untitled session",
                    folder: SessionRegistry.displayFolder($0.cwd ?? ""),
                    lastActivity: Date(timeIntervalSince1970: ($0.lastActivityAt ?? 0) / 1000),
                    isUnread: isUnread(
                        turnEnded: $0.lastTurnEdgeAt ?? 0, focused: $0.lastFocusedAt ?? 0,
                        seen: seen[$0.sessionId] ?? 0, marked: unreadMarks[$0.sessionId] ?? 0
                    ),
                    summary: [$0.postTurnSummary?.needs_action, $0.postTurnSummary?.status_detail]
                        .compactMap { $0 }.first { !$0.isEmpty },
                    cliSessionId: $0.cliSessionId,
                    cwd: $0.cwd
                )
            }
    }
}
