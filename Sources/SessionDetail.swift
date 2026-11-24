import Foundation

enum SessionDetail {
    private static let tailWindows: [UInt64] = [64_000, 512_000, 4_000_000]
    private static let maxLength = 1200

    private static var projectsDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_PROJECTS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    private static var cache: [String: (stamp: String, text: String?)] = [:]

    static func lastAssistantText(of row: SessionRow) -> String? {
        guard let cwd = row.cwd, let sessionId = row.sessionId else { return nil }
        let folder = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let file = projectsDirectory.appendingPathComponent(folder).appendingPathComponent("\(sessionId).jsonl")
        guard let stamp = stamp(of: file) else { return nil }
        if let cached = cache[file.path], cached.stamp == stamp { return cached.text }
        let text = readLastAssistantText(from: file)
        cache[file.path] = (stamp, text)
        return text
    }

    private static func stamp(of file: URL) -> String? {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        return "\(values.fileSize ?? 0)-\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    private static func readLastAssistantText(from file: URL) -> String? {
        for window in tailWindows {
            guard let tail = readTail(of: file, bytes: window) else { return nil }
            for line in tail.split(separator: "\n").reversed() {
                if let text = assistantText(in: line) { return String(text.prefix(maxLength)) }
            }
        }
        return nil
    }

    private static func readTail(of file: URL, bytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func assistantText(in line: Substring) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let blocks = message["content"] as? [[String: Any]]
        else { return nil }
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
