import Foundation

enum SessionState: String, Codable, CaseIterable {
    case needsPermission
    case needsInput
    case unread
    case working
    case idle

    var rank: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    var needsYou: Bool { self == .needsPermission || self == .needsInput }

    var label: String {
        switch self {
        case .needsPermission: return "Needs permission"
        case .needsInput: return "Needs your answer"
        case .unread: return "New reply"
        case .working: return "Working"
        case .idle: return "Done"
        }
    }
}

enum SessionOrigin: String, Codable {
    case desktop
    case terminal
}

struct SessionRecord: Decodable {
    let pid: Int32
    let sessionId: String?
    let cwd: String
    let name: String?
    let status: String?
    let waitingFor: String?
    let startedAt: Double?
    let statusUpdatedAt: Double?
    let entrypoint: String?
    let hostSessionId: String?
    let procStart: String?
    let messagingSocketPath: String?
}

struct SessionRow: Identifiable, Equatable, Codable {
    let pid: Int32
    let sessionId: String?
    let title: String
    let folder: String
    let state: SessionState
    let since: Date?
    let origin: SessionOrigin
    let hostSessionId: String?
    var requests: [PermissionRequest] = []
    var running = true
    var summary: String?
    var cwd: String?
    var agents: AgentProgress?

    static let placeholder = SessionRow(
        pid: 0, sessionId: nil, title: "", folder: "", state: .idle, since: nil, origin: .desktop, hostSessionId: nil
    )

    var id: Int32 { pid }
    var key: String { hostSessionId ?? sessionId ?? "pid-\(pid)" }
    var request: PermissionRequest? { requests.first }

    func withoutRequests(in ids: Set<String>) -> SessionRow {
        var copy = self
        copy.requests.removeAll { ids.contains($0.id) }
        return copy
    }
}

enum SessionRegistry {
    private static let pidReuseTolerance: TimeInterval = 300

    static func loadRecords() -> [SessionRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: WidgetPaths.sessions, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file in
                (try? Data(contentsOf: file)).flatMap { try? decoder.decode(SessionRecord.self, from: $0) }
            }
            .filter(isLive)
    }

    static func makeRow(_ record: SessionRecord, requests: [PermissionRequest], desktop: DesktopSession? = nil) -> SessionRow {
        let state = refine(state(of: record), with: desktop)
        return SessionRow(
            pid: record.pid,
            sessionId: record.sessionId,
            title: displayTitle(record),
            folder: displayFolder(record.cwd),
            state: state,
            since: record.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            origin: record.entrypoint == "claude-desktop" ? .desktop : .terminal,
            hostSessionId: record.hostSessionId,
            requests: state.needsYou ? requests : [],
            summary: summary(for: state, desktop: desktop),
            cwd: record.cwd
        )
    }

    static func refine(_ state: SessionState, with desktop: DesktopSession?) -> SessionState {
        state == .idle && desktop?.isUnread == true ? .unread : state
    }

    static func summary(for state: SessionState, desktop: DesktopSession?) -> String? {
        guard [.needsInput, .unread, .idle].contains(state), let text = desktop?.summary, !text.isEmpty else { return nil }
        return text
    }

    static func state(of record: SessionRecord) -> SessionState {
        switch record.status {
        case "waiting":
            let isPermission = (record.waitingFor ?? "").localizedCaseInsensitiveContains("permission")
            return isPermission ? .needsPermission : .needsInput
        case "busy":
            return .working
        default:
            return .idle
        }
    }

    static func isListedBefore(_ a: SessionRow, _ b: SessionRow) -> Bool {
        if a.state.rank != b.state.rank { return a.state.rank < b.state.rank }
        let aTime = a.since ?? .distantPast
        let bTime = b.since ?? .distantPast
        if aTime == bTime { return a.pid < b.pid }
        return a.state.needsYou ? aTime < bTime : aTime > bTime
    }

    private static func isLive(_ record: SessionRecord) -> Bool {
        guard kill(record.pid, 0) == 0 || errno == EPERM else { return false }
        guard let startedAt = record.startedAt, let processStart = ProcessClock.startTime(of: record.pid) else { return true }
        return abs(startedAt / 1000 - processStart.timeIntervalSince1970) < pidReuseTolerance
    }

    private static func displayTitle(_ record: SessionRecord) -> String {
        if let name = record.name, !name.isEmpty { return name }
        return displayFolder(record.cwd)
    }

    static func displayFolder(_ cwd: String) -> String {
        if cwd.contains("/Claude/scratch-workspaces/") { return "No folder" }
        return URL(fileURLWithPath: cwd).pathComponents.suffix(2).joined(separator: "/")
    }
}
