import SwiftUI

enum ReplyMetrics {
    static let width: CGFloat = 780
    static let height: CGFloat = 660
    static let minWidth: CGFloat = 560
    static let minHeight: CGFloat = 440
    static let corner: CGFloat = 22
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)
}

final class ReplyZoom: ObservableObject {
    static let shared = ReplyZoom()
    private static let key = "replyFontScale"

    @Published private(set) var scale: CGFloat

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.key)
        scale = stored > 0 ? CGFloat(stored) : 1
    }

    func zoomIn() { set(scale + 0.1) }
    func zoomOut() { set(scale - 0.1) }
    func reset() { set(1) }

    private func set(_ value: CGFloat) {
        scale = min(2.0, max(0.7, (value * 10).rounded() / 10))
        UserDefaults.standard.set(Double(scale), forKey: Self.key)
    }
}

struct ReplyView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject private var zoom = ReplyZoom.shared
    let onClose: () -> Void

    @State private var text = ""
    @State private var picks: [String: Set<String>] = [:]
    @State private var appeared = false
    @State private var shownKey: String?
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if let row = store.replyRow {
                content(for: row)
            }
        }
        .frame(minWidth: ReplyMetrics.minWidth, maxWidth: .infinity, minHeight: ReplyMetrics.minHeight, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ReplyMetrics.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ReplyMetrics.corner, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onReceive(store.$replyKey) { key in
            appeared = false
            guard let key else { return }
            if key != shownKey { text = "" }
            shownKey = key
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { appeared = true }
                focused = true
            }
        }
    }

    private func content(for row: SessionRow) -> some View {
        VStack(spacing: 0) {
            header(for: row)
            Divider().opacity(0.5)
            ScrollView {
                MarkdownText(text: store.detail ?? row.summary ?? "No recent message found.", size: 15 * zoom.scale)
                    .equatable()
                    .textSelection(.enabled)
                    .padding(22)
            }
            if row.state == .needsPermission { permissionNotice(for: row) }
            if let request = row.request, request.isQuestion { questionPanel(for: request) }
            composer(for: row)
        }
    }

    private func header(for row: SessionRow) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Circle().fill(row.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 19 * zoom.scale, weight: .semibold)).lineLimit(1)
                Text("\(row.running ? row.state.label : "Not running") · \(row.folder)")
                    .font(.system(size: 13 * zoom.scale)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { store.open(row) } label: {
                Label("Open in Desktop", systemImage: "arrow.up.forward.app").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(PillButtonStyle())
            Button { store.openTerminal(row) } label: {
                Label("Open in Terminal", systemImage: "terminal").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(PillButtonStyle())
            if row.hostSessionId != nil {
                CircleIconButton(symbol: "envelope.badge", size: 28, hoverColor: StatusPalette.unread) { store.markUnread(row) }
                    .help("Mark as unread and close, to come back to it later")
            }
            CircleIconButton(symbol: "questionmark", size: 28) { store.openShortcuts() }
                .help("Shortcuts & tips (⌘/)")
            CircleIconButton(symbol: "xmark", size: 28, action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func permissionNotice(for row: SessionRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Waiting for your permission", systemImage: "lock.shield.fill")
                .font(.system(size: 13 * zoom.scale, weight: .semibold))
                .foregroundStyle(StatusPalette.permission)
            if let request = row.request {
                RequestCard(request: request, moreCount: row.requests.count - 1) { decision in
                    store.decide(request, decision)
                }
            } else {
                Text("A typed reply can't approve a permission request. Answer it in Claude Desktop or Terminal, or install the Allow / Deny hook (see the README) to answer it here.")
                    .font(.system(size: 13 * zoom.scale)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StatusPalette.permission.opacity(0.1)))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func questionPanel(for request: PermissionRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Claude is asking you", systemImage: "questionmark.bubble.fill")
                    .font(.system(size: 13 * zoom.scale, weight: .semibold))
                    .foregroundStyle(StatusPalette.answer)
                ForEach(Array(request.questions.enumerated()), id: \.offset) { _, question in
                    VStack(alignment: .leading, spacing: 8) {
                        if !question.header.isEmpty {
                            Text(question.header.uppercased()).font(.system(size: 11 * zoom.scale, weight: .bold)).foregroundStyle(.secondary)
                        }
                        Text(question.question).font(.system(size: 15 * zoom.scale, weight: .semibold))
                        ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                            optionRow(option, in: question, of: request)
                        }
                    }
                }
                if !request.canAnswerInline {
                    Button("Submit answers") { submit(request) }
                        .buttonStyle(ActionButtonStyle(color: StatusPalette.answer))
                        .disabled(!allAnswered(request))
                        .opacity(allAnswered(request) ? 1 : 0.4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: questionPanelHeight(for: request))
        .layoutPriority(1)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StatusPalette.answer.opacity(0.1)))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func questionPanelHeight(for request: PermissionRequest) -> CGFloat {
        let perQuestion = request.questions.map { 56 + CGFloat($0.options.count) * 66 }.reduce(0, +)
        let submit: CGFloat = request.canAnswerInline ? 0 : 52
        return min(76 + perQuestion + submit, 360) * zoom.scale
    }

    private func optionRow(_ option: AskOption, in question: AskQuestion, of request: PermissionRequest) -> some View {
        let selected = picks[question.question]?.contains(option.label) == true
        return Button {
            if request.canAnswerInline {
                store.answer(request, [question.question: option.label])
            } else {
                toggle(option.label, in: question)
            }
        } label: {
            HStack(spacing: 10) {
                if !request.canAnswerInline {
                    Image(systemName: selected ? (question.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle") : (question.multiSelect ? "square" : "circle"))
                        .foregroundStyle(selected ? StatusPalette.answer : Color.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.system(size: 14 * zoom.scale, weight: .semibold))
                    if !option.description.isEmpty {
                        Text(option.description).font(.system(size: 12 * zoom.scale)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(selected ? 0.16 : 0.08)))
            .hoverHighlight(cornerRadius: 10, opacity: 0.08)
        }
        .buttonStyle(PressScaleStyle(lifts: false))
    }

    private func toggle(_ label: String, in question: AskQuestion) {
        var current = picks[question.question] ?? []
        if question.multiSelect {
            if current.contains(label) { current.remove(label) } else { current.insert(label) }
        } else {
            current = [label]
        }
        picks[question.question] = current
    }

    private func allAnswered(_ request: PermissionRequest) -> Bool {
        request.questions.allSatisfy { !(picks[$0.question] ?? []).isEmpty }
    }

    private func submit(_ request: PermissionRequest) {
        var answers: [String: String] = [:]
        for question in request.questions {
            let chosen = question.options.map(\.label).filter { picks[question.question]?.contains($0) == true }
            answers[question.question] = chosen.joined(separator: ", ")
        }
        store.answer(request, answers)
        picks = [:]
    }

    private func composer(for row: SessionRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = store.sendStatus {
                Text(status).font(.system(size: 13)).foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 10) {
                TextField(placeholder(for: row), text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17 * zoom.scale))
                    .lineLimit(3...9)
                    .focused($focused)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            Self.insertNewline()
                        } else {
                            send(row)
                        }
                        return .handled
                    }
                HStack {
                    Text("Return to send · Shift-Return for a new line")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                    Spacer()
                    Button { send(row) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ReplyMetrics.accent))
                            .opacity(canSend ? 1 : 0.4)
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(!canSend)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        }
        .padding(16)
    }

    private static func insertNewline() {
        let editor = NSApp.windows.compactMap { $0.firstResponder as? NSTextView }.first
        editor?.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func placeholder(for row: SessionRow) -> String {
        if let request = row.request, request.questions.count == 1 { return "Or type your own answer…" }
        return row.state == .needsPermission ? "Add instructions (this does not approve the request)…" : "Reply to this session…"
    }

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send(_ row: SessionRow) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        if let request = row.request, request.questions.count == 1 {
            store.answer(request, [request.questions[0].question: message])
            text = ""
            return
        }
        if store.send(message, to: row) { text = "" }
    }
}
