import AppKit
import Foundation

enum HookInstaller {
    private static var files: [URL] {
        ClaudeConfig.settingsFiles.filter { FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) }
    }

    private static func backupFile(for file: URL) -> URL {
        file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".bak-claude-tracker")
    }

    private static func display(_ file: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return file.path.hasPrefix(home) ? "~" + file.path.dropFirst(home.count) : file.path
    }

    private static var command: String { "\"\(WidgetPaths.installedHook.path)\"" }

    private static func hasHook(_ file: URL) -> Bool {
        guard let settings = load(file) else { return false }
        return permissionEntries(in: settings).contains(where: containsOurHook)
    }

    static func isInstalled() -> Bool {
        let targets = files
        return !targets.isEmpty && targets.allSatisfy(hasHook)
    }

    static func install() throws {
        for file in files {
            try change(file) { entries in
                entries.filter { !containsOurHook($0) } + [["hooks": [["type": "command", "command": command, "timeout": 630]]]]
            }
        }
    }

    static func uninstall() throws {
        for file in files where hasHook(file) {
            try change(file) { entries in entries.filter { !containsOurHook($0) } }
        }
    }

    static func confirmAndToggle() {
        let installing = !isInstalled()
        let places = files.map(display).joined(separator: "\n")
        let alert = NSAlert()
        alert.messageText = installing ? "Set up Allow / Deny buttons?" : "Remove the Allow / Deny hook?"
        alert.informativeText = installing
            ? "This adds one hook to each of these files so permission requests can be answered from the widget:\n\(places)\n\nA backup is saved next to each one. It only applies to Claude sessions started after this: restart sessions that are already open."
            : "This removes the hook from:\n\(places)\n\nA backup is saved next to each one."
        alert.addButton(withTitle: installing ? "Add hook" : "Remove hook")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if installing { try install() } else { try uninstall() }
        } catch {
            let failure = NSAlert()
            failure.messageText = "Could not update settings.json"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    private static func load(_ settingsFile: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsFile) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func permissionEntries(in settings: [String: Any]) -> [[String: Any]] {
        ((settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]) ?? []
    }

    private static func containsOurHook(_ entry: [String: Any]) -> Bool {
        ((entry["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String) == command }
    }

    private static func change(_ settingsFile: URL, _ transform: ([[String: Any]]) -> [[String: Any]]) throws {
        let backupFile = backupFile(for: settingsFile)
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsFile.path) {
            guard let existing = load(settingsFile) else { throw CocoaError(.fileReadCorruptFile) }
            settings = existing
            try? FileManager.default.removeItem(at: backupFile)
            try FileManager.default.copyItem(at: settingsFile, to: backupFile)
        } else {
            try FileManager.default.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let updated = transform(permissionEntries(in: settings))
        if updated.isEmpty { hooks.removeValue(forKey: "PermissionRequest") } else { hooks["PermissionRequest"] = updated }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let permissions = (try? FileManager.default.attributesOfItem(atPath: settingsFile.path)[.posixPermissions]) as? NSNumber
        try data.write(to: settingsFile, options: .atomic)
        if let permissions { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: settingsFile.path) }
    }
}
