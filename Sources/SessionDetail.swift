import Foundation

struct AgentProgress: Equatable, Codable {
    let done: Int
    let total: Int

    var isRunning: Bool { done < total }
}

enum SessionDetail {
    private static let tailWindows: [UInt64] = [256_000, 2_000_000, 8_000_000]
    private static let maxLength = 200_000
    private static let agentTools: Set<String> = ["Agent", "Task"]

    private static var projectsDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_PROJECTS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    private struct Analysis {
        let text: String?
        let agents: AgentProgress?
    }

    private static var cache: [String: (stamp: String, analysis: Analysis)] = [:]
    private static let cacheLock = NSLock()

    static func lastAssistantText(of row: SessionRow) -> String? { analysis(of: row)?.text }

    static func agentProgress(of row: SessionRow) -> AgentProgress? { analysis(of: row)?.agents }

    private static func analysis(of row: SessionRow) -> Analysis? {
        guard let cwd = row.cwd, let sessionId = row.sessionId else { return nil }
        let folder = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let file = projectsDirectory.appendingPathComponent(folder).appendingPathComponent("\(sessionId).jsonl")
        guard let stamp = stamp(of: file) else { return nil }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[file.path], cached.stamp == stamp { return cached.analysis }
        guard let fresh = analyze(file) else { return nil }
        cache[file.path] = (stamp, fresh)
        return fresh
    }

    private static func stamp(of file: URL) -> String? {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        return "\(values.fileSize ?? 0)-\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    private static func analyze(_ file: URL) -> Analysis? {
        var result: Analysis?
        for window in tailWindows {
            guard let (tail, coversWholeFile) = readTail(of: file, bytes: window) else { return nil }
            var text: String?
            var started: [String] = []
            var finished = Set<String>()
            var sawPrompt = false
            for line in tail.split(separator: "\n") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      object["isSidechain"] as? Bool != true,
                      let message = object["message"] as? [String: Any]
                else { continue }
                switch object["type"] as? String {
                case "assistant":
                    let blocks = message["content"] as? [[String: Any]] ?? []
                    if let found = textOf(blocks) { text = found }
                    for block in blocks where block["type"] as? String == "tool_use" {
                        if let name = block["name"] as? String, agentTools.contains(name), let id = block["id"] as? String {
                            started.append(id)
                        }
                    }
                case "user":
                    if object["isMeta"] as? Bool == true { continue }
                    if let content = message["content"] as? String, !content.isEmpty {
                        if isInjected(content) { continue }
                        sawPrompt = true
                        started = []
                        finished = []
                    } else if let blocks = message["content"] as? [[String: Any]] {
                        let results = blocks.filter { $0["type"] as? String == "tool_result" }
                        for block in results { if let id = block["tool_use_id"] as? String { finished.insert(id) } }
                        if results.isEmpty, blocks.contains(where: { $0["type"] as? String == "text" }) {
                            sawPrompt = true
                            started = []
                            finished = []
                        }
                    }
                default:
                    continue
                }
            }
            let agents = started.isEmpty ? nil : AgentProgress(done: started.filter { finished.contains($0) }.count, total: started.count)
            result = Analysis(text: text.map { String($0.prefix(maxLength)) }, agents: agents)
            if sawPrompt || coversWholeFile { break }
        }
        return result
    }

    private static let injectedPrefixes = ["Another Claude session sent a message", "<task-notification", "<system-reminder"]

    private static func isInjected(_ content: String) -> Bool {
        injectedPrefixes.contains { content.hasPrefix($0) }
    }

    private static func textOf(_ blocks: [[String: Any]]) -> String? {
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func readTail(of file: URL, bytes: UInt64) -> (String, Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return (String(decoding: data, as: UTF8.self), size <= bytes)
    }
}
