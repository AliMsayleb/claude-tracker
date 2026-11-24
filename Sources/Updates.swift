import AppKit
import CryptoKit

struct ReleaseInfo: Equatable {
    let version: String
    let notes: String
    let zipURL: URL
    let checksumURL: URL
}

enum UpdateError: LocalizedError {
    case network(String)
    case noDownload
    case checksumMismatch
    case unpackFailed
    case notAnInstalledApp

    var errorDescription: String? {
        switch self {
        case .network(let detail): return "Could not reach GitHub (\(detail))."
        case .noDownload: return "The latest release has no downloadable app."
        case .checksumMismatch: return "The download is corrupted (checksum mismatch)."
        case .unpackFailed: return "The download could not be unpacked."
        case .notAnInstalledApp: return "Updates only work for the installed app (Claude Tracker.app)."
        }
    }
}

enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func parts(_ version: String) -> [Int] {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = parts(candidate)
        let b = parts(installed)
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}

enum UpdateService {
    static let appName = "Claude Tracker.app"
    private static let defaultEndpoint = "https://api.github.com/repos/AliMsayleb/claude-tracker/releases/latest"

    static var endpoint: URL {
        let override = ProcessInfo.processInfo.environment["CLAUDE_TRACKER_UPDATE_URL"]
        return URL(string: override ?? defaultEndpoint) ?? URL(string: defaultEndpoint)!
    }

    static func fetchLatest() throws -> ReleaseInfo {
        let data = try fetch(endpoint)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String
        else { throw UpdateError.network("unexpected response") }
        let assets = (object["assets"] as? [[String: Any]]) ?? []
        func url(named name: String) -> URL? {
            assets.first { $0["name"] as? String == name }.flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
        }
        guard let zip = url(named: "Claude-Tracker.zip"), let checksum = url(named: "Claude-Tracker.zip.sha256") else {
            throw UpdateError.noDownload
        }
        return ReleaseInfo(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                           notes: object["body"] as? String ?? "", zipURL: zip, checksumURL: checksum)
    }

    static func download(_ release: ReleaseInfo, into directory: URL) throws -> URL {
        let zipData = try fetch(release.zipURL)
        let checksumText = String(decoding: try fetch(release.checksumURL), as: UTF8.self)
        let expected = checksumText.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        let actual = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
        guard expected == actual else { throw UpdateError.checksumMismatch }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let zip = directory.appendingPathComponent("update.zip")
        try zipData.write(to: zip)
        let unpacked = directory.appendingPathComponent("unpacked")
        try? FileManager.default.removeItem(at: unpacked)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) else { throw UpdateError.unpackFailed }
        let app = unpacked.appendingPathComponent(appName)
        guard FileManager.default.fileExists(atPath: app.path),
              run("/usr/bin/codesign", ["--verify", "--deep", app.path])
        else { throw UpdateError.unpackFailed }
        return app
    }

    static func script(waitingFor pid: Int32, newApp: URL, destination: URL) -> String {
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return """
        #!/bin/bash
        pid=\(pid)
        while [ "$pid" -gt 0 ] && kill -0 "$pid" 2> /dev/null; do sleep 0.3; done
        rm -rf \(quoted(destination.path))
        ditto \(quoted(newApp.path)) \(quoted(destination.path))
        xattr -dr com.apple.quarantine \(quoted(destination.path)) 2> /dev/null
        [ -n "$SKIP_LAUNCH" ] || open \(quoted(destination.path))

        """
    }

    private static func fetch(_ url: URL) throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("ClaudeTracker/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let done = DispatchSemaphore(value: 0)
        var result: Result<Data, UpdateError> = .failure(.network("no answer"))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(.network(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(.network("HTTP \(http.statusCode)"))
            } else if let data {
                result = .success(data)
            }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }

    private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

final class UpdateController {
    private static let autoKey = "autoCheckUpdates"
    private static let lastCheckKey = "lastUpdateCheck"

    private let store: SessionStore
    private var latest: ReleaseInfo?
    private var installing = false
    private var timer: Timer?

    init(store: SessionStore) {
        self.store = store
        UserDefaults.standard.register(defaults: [Self.autoKey: true])
    }

    func startAutomaticChecks() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
    }

    func checkNow() { check(userInitiated: true) }

    func installAvailable() {
        if let latest { promptToInstall(latest) } else { check(userInitiated: true) }
    }

    private func checkIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.autoKey) else { return }
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        check(userInitiated: false)
    }

    private func check(userInitiated: Bool) {
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try UpdateService.fetchLatest() }
            DispatchQueue.main.async { self.handle(result, userInitiated: userInitiated) }
        }
    }

    private func handle(_ result: Result<ReleaseInfo, Error>, userInitiated: Bool) {
        switch result {
        case .success(let release):
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            if AppVersion.isNewer(release.version, than: AppVersion.current) {
                latest = release
                store.setUpdate(release.version)
                if userInitiated { promptToInstall(release) }
            } else {
                latest = nil
                store.setUpdate(nil)
                if userInitiated { show("You're up to date", "Claude Tracker \(AppVersion.current) is the latest version.") }
            }
        case .failure(let error):
            if userInitiated { show("Could not check for updates", error.localizedDescription) }
        }
    }

    private func promptToInstall(_ release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "Claude Tracker \(release.version) is available"
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)
        alert.informativeText = "You have \(AppVersion.current).\n\n\(notes)\n\nThis downloads the update, replaces the app and restarts it. macOS may ask you to allow the ⌘ shortcut (Accessibility) again."
        alert.addButton(withTitle: "Install and restart")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, !installing else { return }
        install(release)
    }

    private func install(_ release: ReleaseInfo) {
        let destination = Bundle.main.bundleURL
        guard destination.pathExtension == "app" else {
            show("Cannot update", UpdateError.notAnInstalledApp.localizedDescription)
            return
        }
        installing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("claude-tracker-update-\(UUID().uuidString)")
            let result = Result { try UpdateService.download(release, into: work) }
            DispatchQueue.main.async {
                self.installing = false
                switch result {
                case .success(let newApp): self.relaunch(into: newApp, destination: destination)
                case .failure(let error): self.show("Update failed", error.localizedDescription)
                }
            }
        }
    }

    private func relaunch(into newApp: URL, destination: URL) {
        let script = UpdateService.script(waitingFor: ProcessInfo.processInfo.processIdentifier, newApp: newApp, destination: destination)
        let file = WidgetPaths.home.appendingPathComponent("update.sh")
        try? FileManager.default.createDirectory(at: WidgetPaths.home, withIntermediateDirectories: true)
        guard (try? script.write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [file.path]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        guard (try? helper.run()) != nil else { return }
        NSApp.terminate(nil)
    }

    private func show(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
