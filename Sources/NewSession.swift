import AppKit

enum NewSessionTarget: String, CaseIterable, Identifiable {
    case desktop
    case terminal
    case background
    case backgroundDesktop

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .desktop: return "macwindow"
        case .terminal: return "terminal"
        case .background: return "moon.zzz"
        case .backgroundDesktop: return "macwindow.badge.plus"
        }
    }

    var title: String {
        switch self {
        case .desktop: return "Desktop"
        case .terminal: return "Terminal"
        case .background: return "Background"
        case .backgroundDesktop: return "Background → Desktop"
        }
    }

    var explanation: String {
        switch self {
        case .desktop: return "Opens Claude Desktop's new-session screen with the folder and prompt filled in. Press Enter there to send."
        case .terminal: return "Opens Terminal and starts a Claude Code session in that folder with your prompt."
        case .background: return "Starts the session with no window. It shows up here; open it any time. Permission prompts can be answered here too."
        case .backgroundDesktop: return "Starts the session now. When its first answer is ready, an Open in Desktop button appears on its row in the widget. Nothing opens until you click it."
        }
    }
}

struct NewSessionRequest: Equatable {
    let folder: String?
    let prompt: String
    let target: NewSessionTarget
}

enum NewSessionError: LocalizedError, Equatable {
    case emptyPrompt
    case promptTooLong(Int)
    case badFolder
    case claudeNotFound
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyPrompt: return "Write what you want Claude to do."
        case .promptTooLong(let limit): return "That prompt is too long for this option (limit \(limit) characters)."
        case .badFolder: return "Pick a folder that exists."
        case .claudeNotFound: return "Claude Code (claude) was not found. Install it, then try again."
        case .launchFailed(let detail): return "Could not start the session: \(detail)"
        }
    }
}

enum NewSessionLauncher {
    static let maxPrompt = 20_000
    static let maxDesktopPrompt = 2_000

    static func validate(_ request: NewSessionRequest) throws {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw NewSessionError.emptyPrompt }
        let limit = request.target == .desktop ? maxDesktopPrompt : maxPrompt
        guard prompt.count <= limit else { throw NewSessionError.promptTooLong(limit) }
        guard let folder = request.folder else { return }
        var isDirectory: ObjCBool = false
        guard folder.hasPrefix("/"), !folder.contains("\n"),
              FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw NewSessionError.badFolder }
    }

    private static var ownScratchFolder: String { WidgetPaths.home.appendingPathComponent("no-folder").path }

    static var scratchFolder: String { desktopScratchFolder() ?? ownScratchFolder }

    static func desktopScratchFolder() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = environment["CLAUDE_TRACKER_SCRATCH_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent("Library/Application Support/Claude/scratch-workspaces")
        let settings = environment["CLAUDE_TRACKER_CLAUDE_JSON"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: settings),
              let projects = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["projects"] as? [String: [String: Any]]
        else { return nil }
        func children(_ url: URL) -> [URL] {
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        }
        let candidates = children(root).flatMap(children).flatMap(children).filter { $0.lastPathComponent.hasPrefix("scratch-") }
        return candidates
            .filter { candidate in
                projects.contains { URL(fileURLWithPath: $0.key).resolvingSymlinksInPath().path == candidate.resolvingSymlinksInPath().path
                    && $0.value["hasTrustDialogAccepted"] as? Bool == true }
            }
            .max { $0.lastPathComponent < $1.lastPathComponent }?.path
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func desktopURL(for request: NewSessionRequest) -> URL? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = request.folder.map { "&folder=\(encode($0))" } ?? ""
        return URL(string: "claude://code/new?q=\(encode(prompt))\(folder)")
    }

    static func resumeURL(sessionId: String) -> URL? {
        guard UUID(uuidString: sessionId) != nil else { return nil }
        return URL(string: "claude://resume?session=\(sessionId)")
    }

    static func sessionName(for prompt: String) -> String {
        let firstLine = prompt.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? "New session"
        return String(firstLine.prefix(40))
    }

    private static var extraArguments: String {
        ProcessInfo.processInfo.environment["CLAUDE_TRACKER_CLAUDE_ARGS"] ?? ""
    }

    private static func changeDirectoryLine(for request: NewSessionRequest) -> String {
        guard let folder = request.folder else {
            return "mkdir -p -- \(shellQuote(scratchFolder)) && cd -- \(shellQuote(scratchFolder)) || exit 1"
        }
        return "cd -- \(shellQuote(folder)) || exit 1"
    }

    static func terminalScript(for request: NewSessionRequest) -> String {
        """
        #!/bin/zsh
        \(changeDirectoryLine(for: request))
        command -v claude > /dev/null || { echo "Claude Code (claude) was not found in your PATH."; read -r; exit 1; }
        exec claude \(extraArguments) -- \(shellQuote(request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)))

        """
    }

    static func backgroundScript(for request: NewSessionRequest) -> String {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        #!/bin/zsh
        \(changeDirectoryLine(for: request))
        command -v claude > /dev/null || { echo "claude not found"; exit 127; }
        exec claude --bg --name \(shellQuote(sessionName(for: prompt))) \(extraArguments) -- \(shellQuote(prompt))

        """
    }

    static func start(_ request: NewSessionRequest, completion: @escaping (Result<String, NewSessionError>) -> Void) {
        do { try validate(request) } catch {
            completion(.failure(error as? NewSessionError ?? .launchFailed(error.localizedDescription)))
            return
        }
        switch request.target {
        case .desktop:
            guard let url = desktopURL(for: request), NSWorkspace.shared.open(url) else {
                completion(.failure(.launchFailed("Claude Desktop did not accept the link")))
                return
            }
            completion(.success("Opened in Claude Desktop. Press Enter there to send."))
        case .terminal:
            guard let file = writeScript(terminalScript(for: request), named: "new-\(UUID().uuidString).command") else {
                completion(.failure(.launchFailed("could not write the launch script")))
                return
            }
            NSWorkspace.shared.open(file)
            completion(.success("Opened in Terminal."))
        case .background:
            runInBackground(request, completion: completion)
        case .backgroundDesktop:
            runInBackground(request) { result in
                if case .success = result { completion(.success("Started. Its row gets an Open in Desktop button when the first answer is ready.")) } else { completion(result) }
            }
        }
    }

    static func recentFolders(limit: Int = 12) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in DesktopSessions.all().sorted(by: { $0.lastActivity > $1.lastActivity }) {
            guard let cwd = session.cwd, cwd.hasPrefix("/"), !cwd.contains("/Claude/scratch-workspaces/"),
                  seen.insert(cwd).inserted
            else { continue }
            result.append(cwd)
            if result.count == limit { break }
        }
        return result
    }

    static func openInDesktop(sessionId: String) {
        guard let url = resumeURL(sessionId: sessionId) else { return }
        _ = runClaude("stop \(sessionId.prefix(8))")
        DispatchQueue.main.async {
            let previousApp = NSWorkspace.shared.frontmostApplication
            NSWorkspace.shared.open(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { previousApp?.activate() }
        }
    }

    private static func runClaude(_ arguments: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "claude \(arguments) > /dev/null 2>&1"]
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func writeScript(_ script: String, named name: String) -> URL? {
        let directory = WidgetPaths.home.appendingPathComponent("launch")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeOldScripts(in: directory)
        let file = directory.appendingPathComponent(name)
        guard (try? script.write(to: file, atomically: true, encoding: .utf8)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private static func removeOldScripts(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            if Date().timeIntervalSince(modified) > 7 * 24 * 3600 { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func runInBackground(_ request: NewSessionRequest, completion: @escaping (Result<String, NewSessionError>) -> Void) {
        guard let file = writeScript(backgroundScript(for: request), named: "new-\(UUID().uuidString).sh") else {
            completion(.failure(.launchFailed("could not write the launch script")))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", file.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var outcome: Result<String, NewSessionError>
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0 {
                    let lines = output.split(separator: "\n").map(String.init)
                    outcome = .success(lines.first { $0.hasPrefix("backgrounded") } ?? lines.first ?? "Started in the background.")
                } else if process.terminationStatus == 127 {
                    outcome = .failure(.claudeNotFound)
                } else {
                    outcome = .failure(.launchFailed(String(output.prefix(300))))
                }
            } catch {
                outcome = .failure(.launchFailed(error.localizedDescription))
            }
            try? FileManager.default.removeItem(at: file)
            DispatchQueue.main.async { completion(outcome) }
        }
    }
}

final class NewSessionModel: ObservableObject {
    private static let targetKey = "newSessionTarget"

    @Published var folder: String?
    @Published var prompt = ""
    @Published var target: NewSessionTarget {
        didSet { UserDefaults.standard.set(target.rawValue, forKey: Self.targetKey) }
    }
    @Published var message: String?
    @Published var messageIsError = false
    @Published var starting = false
    @Published private(set) var recentFolders: [String] = []

    var onFinished: () -> Void = {}
    private let starter: (NewSessionRequest, @escaping (Result<String, NewSessionError>) -> Void) -> Void

    init(starter: @escaping (NewSessionRequest, @escaping (Result<String, NewSessionError>) -> Void) -> Void) {
        self.starter = starter
        let defaults = UserDefaults.standard
        folder = nil
        target = NewSessionTarget(rawValue: defaults.string(forKey: Self.targetKey) ?? "") ?? .desktop
    }

    func forgetSavedChoices() {
        folder = nil
        target = .desktop
    }

    func prepare() {
        recentFolders = NewSessionLauncher.recentFolders()
        message = nil
        starting = false
    }

    func start() {
        guard !starting else { return }
        starting = true
        message = nil
        starter(NewSessionRequest(folder: folder, prompt: prompt, target: target)) { [weak self] result in
            guard let self else { return }
            self.starting = false
            switch result {
            case .success:
                self.prompt = ""
                self.onFinished()
            case .failure(let error):
                self.message = error.localizedDescription
                self.messageIsError = true
            }
        }
    }
}

enum HandOffCenter {
    static func handOff(_ sessionId: String) {
        DispatchQueue.global(qos: .userInitiated).async { NewSessionLauncher.openInDesktop(sessionId: sessionId) }
    }
}
