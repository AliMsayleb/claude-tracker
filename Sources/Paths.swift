import Foundation

enum WidgetPaths {
    static var home: URL { directory(overriddenBy: "CLAUDE_WIDGET_HOME", fallback: ".claude-widget") }
    static var requests: URL { home.appendingPathComponent("requests") }
    static var heartbeat: URL { home.appendingPathComponent("heartbeat") }
    static var installedHook: URL { home.appendingPathComponent("permission-hook.sh") }

    private static func directory(overriddenBy variable: String, fallback: String) -> URL {
        if let override = ProcessInfo.processInfo.environment[variable], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(fallback)
    }
}

enum Console {
    static func line(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
}
