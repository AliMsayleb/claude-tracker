import SwiftUI

enum NewSessionMetrics {
    static let width: CGFloat = 600
    static let height: CGFloat = 540
    static let minWidth: CGFloat = 480
    static let minHeight: CGFloat = 440
}

struct NewSessionView: View {
    @ObservedObject var model: NewSessionModel
    let onClose: () -> Void

    @FocusState private var promptFocused: Bool
    @State private var showTargets = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("New session").font(.system(size: 22, weight: .semibold))
                Spacer()
                CircleIconButton(symbol: "xmark", size: 28, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            folderPicker
            VStack(alignment: .leading, spacing: 8) {
                Text("PROMPT").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                TextField("What should Claude do?", text: $model.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .lineLimit(5...500)
                    .focused($promptFocused)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            NSApp.windows.compactMap { $0.firstResponder as? NSTextView }.first?
                                .insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
                        } else {
                            model.start()
                        }
                        return .handled
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 130, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("START IT IN").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                targetPicker
            }
            if let message = model.message {
                Text(message).font(.system(size: 13)).foregroundStyle(model.messageIsError ? Color.red : Color.secondary)
            }
            HStack {
                Text("Return to start · Shift-Return for a new line").font(.system(size: 12)).foregroundStyle(.tertiary)
                Spacer()
                Button(model.starting ? "Starting…" : "Start session") { model.start() }
                    .buttonStyle(ActionButtonStyle(color: ReplyMetrics.accent))
                    .disabled(model.starting)
            }
        }
        .padding(24)
        .frame(minWidth: NewSessionMetrics.minWidth, maxWidth: .infinity, minHeight: NewSessionMetrics.minHeight, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
        .onAppear {
            promptFocused = true
            for delay in [0.1, 0.25, 0.5, 0.9] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let editor = NSApp.windows.compactMap({ $0.firstResponder as? NSTextView }).first,
                          editor.selectedRange().length > 0, editor.selectedRange().length == editor.string.utf16.count
                    else { return }
                    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                }
            }
        }
    }

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOLDER").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            Menu {
                ForEach(model.recentFolders, id: \.self) { path in
                    Button(Self.display(path)) { model.folder = path }
                }
                if !model.recentFolders.isEmpty { Divider() }
                Button("No folder") { model.folder = nil }
                Button("Choose another folder…") { chooseFolder() }
            } label: {
                HStack {
                    Image(systemName: model.folder == nil ? "folder.badge.minus" : "folder.fill").foregroundStyle(ReplyMetrics.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No folder").font(.system(size: 14, weight: .semibold))
                        Text(model.folder.map(Self.display) ?? "Claude uses a scratch folder, like Desktop does").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)))
                .hoverHighlight(cornerRadius: 12, opacity: 0.08)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    private func targetCard(_ target: NewSessionTarget, showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: target.symbol).foregroundStyle(ReplyMetrics.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(target.title).font(.system(size: 14, weight: .semibold))
                Text(target.explanation).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            } else if target == model.target {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(ReplyMetrics.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var targetPicker: some View {
        Button { showTargets.toggle() } label: {
            targetCard(model.target, showsChevron: true)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)))
                .hoverHighlight(cornerRadius: 12, opacity: 0.08)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showTargets, arrowEdge: .top) {
            VStack(spacing: 2) {
                ForEach(NewSessionTarget.allCases) { target in
                    Button {
                        model.target = target
                        showTargets = false
                    } label: {
                        targetCard(target, showsChevron: false)
                            .hoverHighlight(cornerRadius: 10, opacity: 0.10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(width: 440)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: model.folder ?? FileManager.default.homeDirectoryForCurrentUser.path)
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { model.folder = url.path }
    }

    static func display(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
