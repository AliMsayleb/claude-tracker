import SwiftUI

enum NewSessionMetrics {
    static let width: CGFloat = 600
    static let height: CGFloat = 660
    static let minWidth: CGFloat = 480
    static let minHeight: CGFloat = 580
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    modelPicker
                    effortPicker
                }
                .disabled(!model.target.supportsModelAndEffort)
                .opacity(model.target.supportsModelAndEffort ? 1 : 0.45)
                if !model.target.supportsModelAndEffort {
                    Text("Desktop's new-session link cannot set the model or effort. Pick Terminal, Background or Background → Desktop to use them.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            for delay in stride(from: 0.1, through: 2.0, by: 0.1) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let editor = NSApp.windows.compactMap({ $0.firstResponder as? NSTextView }).first,
                          editor.selectedRange().length > 0, editor.selectedRange().length == editor.string.utf16.count
                    else { return }
                    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                }
            }
        }
    }

    private static let noFolderOption = PickerOption(
        id: "", symbol: "folder.badge.minus", title: "No folder", detail: "Claude uses a scratch folder, like Desktop does"
    )

    private func folderOption(_ path: String) -> PickerOption {
        PickerOption(id: path, symbol: "folder.fill", title: URL(fileURLWithPath: path).lastPathComponent, detail: Self.display(path))
    }

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOLDER").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            RichPicker(
                current: model.folder.map(folderOption) ?? Self.noFolderOption,
                options: [Self.noFolderOption] + model.recentFolders.map(folderOption),
                action: PickerAction(symbol: "folder.badge.plus", title: "Choose another folder…", perform: chooseFolder),
                arrowEdge: .bottom,
                detailLines: 1
            ) { id in model.folder = id.isEmpty ? nil : id }
        }
    }

    private static let modelDetails: [ModelChoice: (String, String)] = [
        .standard: ("circle.dashed", "Uses your Claude Code setting"),
        .fable: ("sparkle", "Latest Fable model"),
        .opus: ("sparkle", "Latest Opus model"),
        .sonnet: ("sparkle", "Latest Sonnet model"),
        .haiku: ("sparkle", "Latest Haiku model"),
    ]

    private static let effortDetails: [EffortChoice: (String, String)] = [
        .standard: ("circle.dashed", "Uses the model's usual effort"),
        .low: ("gauge.with.dots.needle.0percent", "Quick answers, least thinking"),
        .medium: ("gauge.with.dots.needle.33percent", "A balance of speed and depth"),
        .high: ("gauge.with.dots.needle.50percent", "Thinks harder before answering"),
        .xhigh: ("gauge.with.dots.needle.67percent", "Even more thinking"),
        .max: ("gauge.with.dots.needle.100percent", "Most thinking, slowest"),
    ]

    private var modelOptions: [PickerOption] {
        ModelChoice.allCases.map { PickerOption(id: $0.rawValue, symbol: Self.modelDetails[$0]?.0 ?? "sparkle", title: $0.title, detail: Self.modelDetails[$0]?.1 ?? "") }
    }

    private var effortOptions: [PickerOption] {
        EffortChoice.allCases.map { PickerOption(id: $0.rawValue, symbol: Self.effortDetails[$0]?.0 ?? "gauge", title: $0.title, detail: Self.effortDetails[$0]?.1 ?? "") }
    }

    private var targetOptions: [PickerOption] {
        NewSessionTarget.allCases.map { PickerOption(id: $0.rawValue, symbol: $0.symbol, title: $0.title, detail: $0.explanation) }
    }

    private func labelled(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            content()
        }
    }

    func previewList(_ kind: String) -> AnyView {
        switch kind {
        case "folder":
            return AnyView(RichPicker(
                current: Self.noFolderOption,
                options: [Self.noFolderOption] + ["/Users/me/projects/app", "/Users/me/projects/website", "/Users/me/work/api"].map(folderOption),
                action: PickerAction(symbol: "folder.badge.plus", title: "Choose another folder…", perform: {}), detailLines: 1, onSelect: { _ in }
            ).popoverContent)
        case "model":
            return AnyView(RichPicker(current: modelOptions[0], options: modelOptions, popoverWidth: 360, detailLines: 1, onSelect: { _ in }).popoverContent)
        case "effort":
            return AnyView(RichPicker(current: effortOptions[2], options: effortOptions, popoverWidth: 360, detailLines: 1, onSelect: { _ in }).popoverContent)
        default:
            return AnyView(RichPicker(current: targetOptions[3], options: targetOptions, onSelect: { _ in }).popoverContent)
        }
    }

    private var targetPicker: some View {
        RichPicker(
            current: targetOptions.first { $0.id == model.target.rawValue } ?? targetOptions[0],
            options: targetOptions
        ) { id in if let target = NewSessionTarget(rawValue: id) { model.target = target } }
    }

    private var modelPicker: some View {
        labelled("MODEL") {
            RichPicker(
                current: modelOptions.first { $0.id == model.model.rawValue } ?? modelOptions[0],
                options: modelOptions, popoverWidth: 360, detailLines: 1
            ) { id in if let choice = ModelChoice(rawValue: id) { model.model = choice } }
        }
    }

    private var effortPicker: some View {
        labelled("EFFORT") {
            RichPicker(
                current: effortOptions.first { $0.id == model.effort.rawValue } ?? effortOptions[0],
                options: effortOptions, popoverWidth: 360, detailLines: 1
            ) { id in if let choice = EffortChoice(rawValue: id) { model.effort = choice } }
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
