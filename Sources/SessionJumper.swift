import AppKit

enum OpenTarget: String {
    case desktop
    case terminal

    static let key = "openTarget"

    static var current: OpenTarget {
        OpenTarget(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .desktop
    }
}

enum SessionJumper {
    private static let hostSessionPattern = "^local_[A-Za-z0-9-]{1,64}$"
    private static let desktopAppURL = URL(fileURLWithPath: "/Applications/Claude.app")

    static func jump(_ row: SessionRow) {
        NSWorkspace.shared.open(deepLink(for: row) ?? desktopAppURL)
    }

    static func terminalScript(cwd: String, sessionId: String) -> String? {
        let validId = sessionId.range(of: "^[0-9A-Fa-f-]{8,64}$", options: .regularExpression) != nil
        guard validId, cwd.hasPrefix("/"), !cwd.contains("\n") else { return nil }
        let quoted = cwd.replacingOccurrences(of: "'", with: "'\\''")
        return """
        #!/bin/zsh
        cd -- '\(quoted)' || exit 1
        command -v claude > /dev/null || { echo "Claude Code (claude) was not found in your PATH."; read -r; exit 1; }
        exec claude --resume \(sessionId)

        """
    }

    static func openInTerminal(_ row: SessionRow) {
        guard let cwd = row.cwd, let sessionId = row.sessionId, let script = terminalScript(cwd: cwd, sessionId: sessionId) else {
            Console.line("cannot open in Terminal: missing folder or session id")
            return
        }
        let directory = WidgetPaths.home.appendingPathComponent("launch")
        let file = directory.appendingPathComponent("\(sessionId).command")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? script.write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        NSWorkspace.shared.open(file)
    }

    static func deepLink(for row: SessionRow) -> URL? {
        guard let host = row.hostSessionId,
              host.range(of: hostSessionPattern, options: .regularExpression) != nil
        else { return nil }
        return URL(string: "claude://code/continue?session=\(host)")
    }
}
