import SwiftUI

struct ShortcutItem: Identifiable {
    let keys: [String]
    let action: String
    var id: String { keys.joined(separator: "+") + action }
}

struct ShortcutSection: Identifiable {
    let title: String
    let items: [ShortcutItem]
    var id: String { title }
}

enum ShortcutCatalog {
    static let sections: [ShortcutSection] = [
        ShortcutSection(title: "Anywhere", items: [
            ShortcutItem(keys: ["⌘", "⌘"], action: "Double-tap ⌘ to show or hide the widget"),
            ShortcutItem(keys: ["⌘ Space"], action: "Spotlight: type “tracker” to open Claude Tracker again after quitting it"),
        ]),
        ShortcutSection(title: "The widget", items: [
            ShortcutItem(keys: ["Click"], action: "Open a session's popup to read its last message and reply"),
            ShortcutItem(keys: ["⌘", "Click"], action: "Open the session in Claude Desktop (also marks it read)"),
            ShortcutItem(keys: ["Allow", "Deny"], action: "Answer a permission request right in the widget"),
            ShortcutItem(keys: ["+"], action: "Add an existing Desktop session (type to search)"),
            ShortcutItem(keys: ["✕ on a row"], action: "Hover a row and click ✕ to remove it from the widget"),
            ShortcutItem(keys: ["⌄"], action: "Collapse the widget to its header, or expand it again"),
            ShortcutItem(keys: ["Drag header"], action: "Move the widget anywhere"),
            ShortcutItem(keys: ["Drag edge"], action: "Resize from the left, right or bottom edge (the size is remembered)"),
            ShortcutItem(keys: ["Right-click header"], action: "Launch at login, enable the ⌘ shortcut, shortcuts, quit"),
        ]),
        ShortcutSection(title: "The reply popup", items: [
            ShortcutItem(keys: ["Return"], action: "Send your reply"),
            ShortcutItem(keys: ["Shift", "Return"], action: "New line"),
            ShortcutItem(keys: ["Esc"], action: "Close the popup"),
            ShortcutItem(keys: ["⌘", "W"], action: "Close the popup"),
            ShortcutItem(keys: ["⌘", "+"], action: "Bigger text (⌘ = works too)"),
            ShortcutItem(keys: ["⌘", "-"], action: "Smaller text"),
            ShortcutItem(keys: ["⌘", "0"], action: "Reset the text size"),
            ShortcutItem(keys: ["⌘", "Tab"], action: "Switch away and come back; your draft is kept"),
            ShortcutItem(keys: ["⌘", "/"], action: "Show this list"),
            ShortcutItem(keys: ["Drag edge"], action: "Resize the popup (the size is remembered)"),
        ]),
        ShortcutSection(title: "Add a session", items: [
            ShortcutItem(keys: ["Type"], action: "Filter by words from the title or folder"),
            ShortcutItem(keys: ["Return"], action: "Add the first match"),
            ShortcutItem(keys: ["Esc"], action: "Close"),
        ]),
    ]

    static var markdown: String {
        sections.map { section in
            let rows = section.items.map { "| \($0.keys.joined(separator: " ")) | \($0.action) |" }
            return (["### \(section.title)", "", "| Shortcut | What it does |", "|---|---|"] + rows).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

enum ShortcutsMetrics {
    static let width: CGFloat = 600
    static let height: CGFloat = 680
}

struct ShortcutsView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcuts & tips").font(.system(size: 22, weight: .semibold))
                    Text("Everything you can do with Claude Tracker").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 14)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(ShortcutCatalog.sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title.uppercased())
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(ReplyMetrics.accent)
                            ForEach(section.items) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 14) {
                                    HStack(spacing: 4) {
                                        ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in
                                            Text(key)
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .padding(.horizontal, 8).padding(.vertical, 3)
                                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.1)))
                                        }
                                    }
                                    .frame(width: 190, alignment: .leading)
                                    Text(item.action).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .padding(26)
            }
            Divider().opacity(0.5)
            HStack {
                Text("Reopen this any time: right-click the widget header, or press ⌘/ in the popup.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Got it", action: onClose)
                    .buttonStyle(ActionButtonStyle(color: ReplyMetrics.accent))
            }
            .padding(.horizontal, 26).padding(.vertical, 14)
        }
        .frame(width: ShortcutsMetrics.width, height: ShortcutsMetrics.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
    }
}
