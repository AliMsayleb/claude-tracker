import Foundation

struct AskOption: Equatable, Codable {
    let label: String
    let description: String
}

struct AskQuestion: Equatable, Codable {
    let question: String
    let header: String
    let multiSelect: Bool
    let options: [AskOption]
}

struct PermissionRequest: Identifiable, Equatable, Codable {
    let id: String
    let sessionId: String
    let toolName: String
    let detail: String
    let createdAt: Date
    var questions: [AskQuestion] = []

    var isQuestion: Bool { !questions.isEmpty }
    var canAnswerInline: Bool { questions.count == 1 && !questions[0].multiSelect && questions[0].options.count <= 4 }
}

enum PermissionDecision: String {
    case allow
    case deny
}

enum PermissionRequests {
    static let staleAfter: TimeInterval = 660
    static let settleTime: TimeInterval = 5
    static let waitingStartTolerance: TimeInterval = 3

    private static let detailKeys = ["command", "file_path", "path", "url", "pattern", "query", "description"]
    private static let maxDetailLength = 400

    static func load() -> [PermissionRequest] {
        requestFiles()
            .filter { $0.pathExtension == "json" }
            .compactMap(parse)
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func decide(_ request: PermissionRequest, _ decision: PermissionDecision) {
        let target = WidgetPaths.requests.appendingPathComponent("\(request.id).decision")
        try? Data(decision.rawValue.utf8).write(to: target, options: .atomic)
    }

    static func answer(_ request: PermissionRequest, answers: [String: String]) {
        let file = WidgetPaths.requests.appendingPathComponent("\(request.id).json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var input = object["tool_input"] as? [String: Any]
        else { return }
        input["answers"] = answers
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": "allow", "updatedInput": input],
            ],
        ]
        guard let output = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) else { return }
        try? output.write(to: WidgetPaths.requests.appendingPathComponent("\(request.id).decision"), options: .atomic)
    }

    static func discardStale(_ requests: [PermissionRequest], sessions: [SessionRecord], now: Date = Date()) {
        var sessionsById: [String: SessionRecord] = [:]
        for session in sessions {
            if let id = session.sessionId { sessionsById[id] = session }
        }
        for request in requests where isStale(request, session: sessionsById[request.sessionId], now: now) {
            discard(request)
        }
    }

    static func beat() {
        try? FileManager.default.createDirectory(at: WidgetPaths.home, withIntermediateDirectories: true)
        let stamp = String(Date().timeIntervalSince1970)
        FileManager.default.createFile(atPath: WidgetPaths.heartbeat.path, contents: Data(stamp.utf8))
    }

    static func stopBeating() {
        try? FileManager.default.removeItem(at: WidgetPaths.heartbeat)
    }

    static func installHookScript() {
        guard let bundled = Bundle.main.url(forResource: "permission-hook", withExtension: "sh"),
              let script = try? Data(contentsOf: bundled)
        else { return }
        try? FileManager.default.createDirectory(at: WidgetPaths.home, withIntermediateDirectories: true)
        guard (try? Data(contentsOf: WidgetPaths.installedHook)) != script else { return }
        try? script.write(to: WidgetPaths.installedHook, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: WidgetPaths.installedHook.path)
    }

    private static func isStale(_ request: PermissionRequest, session: SessionRecord?, now: Date) -> Bool {
        let age = now.timeIntervalSince(request.createdAt)
        if age > staleAfter { return true }
        if age <= settleTime { return false }
        guard let session, SessionRegistry.state(of: session).needsYou else { return true }
        guard let waitingSince = session.statusUpdatedAt.map({ Date(timeIntervalSince1970: $0 / 1000) }) else { return false }
        return request.createdAt < waitingSince.addingTimeInterval(-waitingStartTolerance)
    }

    private static func discard(_ request: PermissionRequest) {
        for name in ["\(request.id).json", "\(request.id).decision"] {
            try? FileManager.default.removeItem(at: WidgetPaths.requests.appendingPathComponent(name))
        }
    }

    private static func requestFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: WidgetPaths.requests, includingPropertiesForKeys: nil)) ?? []
    }

    private static func parse(_ file: URL) -> PermissionRequest? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = object["session_id"] as? String,
              let toolName = object["tool_name"] as? String
        else { return nil }
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return PermissionRequest(
            id: file.deletingPathExtension().lastPathComponent,
            sessionId: sessionId,
            toolName: toolName,
            detail: detail(from: object["tool_input"] as? [String: Any]),
            createdAt: modified ?? Date(),
            questions: toolName == "AskUserQuestion" ? questions(from: object["tool_input"] as? [String: Any]) : []
        )
    }

    private static func questions(from input: [String: Any]?) -> [AskQuestion] {
        let items = (input?["questions"] as? [[String: Any]]) ?? []
        return items.compactMap { item in
            guard let question = item["question"] as? String else { return nil }
            let options = ((item["options"] as? [[String: Any]]) ?? []).compactMap { option -> AskOption? in
                guard let label = option["label"] as? String else { return nil }
                return AskOption(label: label, description: option["description"] as? String ?? "")
            }
            return AskQuestion(question: question, header: item["header"] as? String ?? "", multiSelect: item["multiSelect"] as? Bool ?? false, options: options)
        }
    }

    private static func detail(from input: [String: Any]?) -> String {
        guard let input else { return "" }
        for key in detailKeys {
            if let value = input[key] as? String, !value.isEmpty { return String(value.prefix(maxDetailLength)) }
        }
        return ""
    }
}
