import AppKit

enum SessionJumper {
    private static let hostSessionPattern = "^local_[A-Za-z0-9-]{1,64}$"
    private static let desktopAppURL = URL(fileURLWithPath: "/Applications/Claude.app")

    static func jump(_ row: SessionRow) {
        NSWorkspace.shared.open(deepLink(for: row) ?? desktopAppURL)
    }

    static func deepLink(for row: SessionRow) -> URL? {
        guard let host = row.hostSessionId,
              host.range(of: hostSessionPattern, options: .regularExpression) != nil
        else { return nil }
        return URL(string: "claude://code/continue?session=\(host)")
    }
}
