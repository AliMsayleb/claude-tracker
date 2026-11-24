import Foundation

enum MessageFailure: LocalizedError {
    case notRunning
    case noKey
    case badSocket
    case connectFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notRunning: return "This session is not running. Open it in Desktop to resume it."
        case .noKey: return "Could not find this session's message key."
        case .badSocket: return "This session has no safe message socket."
        case .connectFailed: return "Could not reach the session. Is it still running?"
        case .writeFailed: return "Sending the message failed."
        }
    }
}

enum SessionMessenger {
    static func send(_ text: String, to row: SessionRow) throws {
        guard row.running, row.pid > 0,
              let record = SessionRegistry.loadRecords().first(where: { $0.pid == row.pid })
        else { throw MessageFailure.notRunning }
        guard let path = record.messagingSocketPath, isOwnSocket(path, pid: record.pid) else { throw MessageFailure.badSocket }
        guard let token = peerToken(for: record) else { throw MessageFailure.noKey }
        try write(lines: [["type": "auth", "token": token], ["type": "user", "message": ["role": "user", "content": text]]], to: path)
    }

    private static func isOwnSocket(_ path: String, pid: Int32) -> Bool {
        guard URL(fileURLWithPath: path).lastPathComponent == "\(pid).sock" else { return false }
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFSOCK && info.st_uid == getuid()
    }

    private static func peerToken(for record: SessionRecord) -> String? {
        let files = (try? FileManager.default.contentsOfDirectory(at: WidgetPaths.sessions, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("\(record.pid).") && file.pathExtension == "key" {
            guard let data = try? Data(contentsOf: file),
                  let key = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = key["peerToken"] as? String
            else { continue }
            if let expected = record.procStart, let actual = key["procStart"] as? String, expected != actual { continue }
            return token
        }
        return nil
    }

    private static func write(lines: [[String: Any]], to path: String) throws {
        let payload = try lines.map { try JSONSerialization.data(withJSONObject: $0) + Data("\n".utf8) }.reduce(Data(), +)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MessageFailure.connectFailed }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw MessageFailure.badSocket }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { destination.copyMemory(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw MessageFailure.connectFailed }

        var sent = 0
        while sent < payload.count {
            let count = payload.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress! + sent, payload.count - sent) }
            guard count > 0 else { throw MessageFailure.writeFailed }
            sent += count
        }
    }
}
