import Foundation

enum ClaudeConfig {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static var home: URL {
        environment["CLAUDE_TRACKER_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private static func paths(from variable: String) -> [URL]? {
        guard let value = environment[variable], !value.isEmpty else { return nil }
        return value.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
    }

    static var directories: [URL] {
        if let explicit = paths(from: "CLAUDE_TRACKER_CONFIG_DIRS") { return unique(explicit) }
        var found = [URL]()
        if let current = environment["CLAUDE_CONFIG_DIR"], !current.isEmpty { found.append(URL(fileURLWithPath: current)) }
        found.append(home.appendingPathComponent(".claude"))
        found.append(home.appendingPathComponent(".config/claude"))
        found += UserDefaults.standard.stringArray(forKey: "extraConfigDirs")?.map { URL(fileURLWithPath: $0) } ?? []
        found += discovered()
        let existing = unique(found).filter(isDirectory)
        return existing.isEmpty ? [home.appendingPathComponent(".claude")] : existing
    }

    static var sessionsDirectories: [URL] {
        paths(from: "CLAUDE_SESSIONS_DIR") ?? directories.map { $0.appendingPathComponent("sessions") }
    }

    static var projectsDirectories: [URL] {
        paths(from: "CLAUDE_PROJECTS_DIR") ?? directories.map { $0.appendingPathComponent("projects") }
    }

    static var settingsFiles: [URL] {
        paths(from: "CLAUDE_SETTINGS_FILE") ?? directories.map { $0.appendingPathComponent("settings.json") }
    }

    private static func discovered() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { entry in
            let name = entry.lastPathComponent
            guard name.hasPrefix(".claude"), name != ".claude-widget", !looksLikeLeftover(name), isDirectory(entry) else { return false }
            return ["sessions", "projects", "settings.json"].contains { FileManager.default.fileExists(atPath: entry.appendingPathComponent($0).path) }
        }
    }

    private static func looksLikeLeftover(_ name: String) -> Bool {
        ["backup", "bak", "old", "copy", "tmp", "archive"].contains { name.localizedCaseInsensitiveContains($0) }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
    }
}
