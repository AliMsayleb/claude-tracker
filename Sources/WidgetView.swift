import AppKit
import SwiftUI

enum RowHoverPreview {
    static var enabled = false
}

enum ClickModifiers {
    static var current: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
}

enum WidgetMetrics {
    static let width: CGFloat = 320
    static let minWidth: CGFloat = 260
    static let headerHeight: CGFloat = 42
    static let rowHeight: CGFloat = 54
    static let cornerRadius: CGFloat = 20
    static let sidePadding: CGFloat = 16
}

enum StatusPalette {
    static let permission = Color.red
    static let answer = Color(red: 0.98, green: 0.50, blue: 0.20)
    static let unread = Color(red: 0.914, green: 0.694, blue: 0.259)
    static let working = Color.blue
    static let done = Color(red: 0.30, green: 0.78, blue: 0.45)
    static let notRunning = Color(red: 0.66, green: 0.52, blue: 0.95)
}

extension SessionState {
    var color: Color {
        switch self {
        case .needsPermission: return StatusPalette.permission
        case .needsInput: return StatusPalette.answer
        case .unread: return StatusPalette.unread
        case .working: return StatusPalette.working
        case .idle: return StatusPalette.done
        }
    }
}

extension SessionRow {
    var color: Color { running ? state.color : StatusPalette.notRunning }
    var pulses: Bool { running && state != .idle }
}

extension PermissionRequest {
    var toolDisplayName: String {
        guard toolName.hasPrefix("mcp__") else { return toolName }
        let tool = toolName.components(separatedBy: "__").last ?? toolName
        return tool.replacingOccurrences(of: "_", with: " ")
    }
}

private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct WidgetView: View {
    @ObservedObject var store: SessionStore
    let resizer: WidgetResizer
    let updates: UpdateController?
    let onQuit: () -> Void

    @AppStorage("collapsed") private var collapsed = false
    @AppStorage("widgetMaxHeight") private var maxHeight: Double = 560
    @AppStorage(OpenTarget.key) private var openTarget = OpenTarget.desktop.rawValue
    @AppStorage("autoCheckUpdates") private var autoUpdates = true
    @State private var measuredListHeight: CGFloat = 0

    private var needsYouCount: Int { store.rows.filter { $0.state.needsYou }.count }

    private var listHeight: CGFloat {
        let estimate = CGFloat(store.rows.count) * WidgetMetrics.rowHeight
        let allowed = max(CGFloat(maxHeight) - WidgetMetrics.headerHeight - 1, WidgetMetrics.rowHeight)
        return min(measuredListHeight > 0 ? measuredListHeight : estimate, allowed)
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(needsYouCount: needsYouCount, collapsed: $collapsed, updateVersion: store.updateVersion, onUpdate: { updates?.installAvailable() }, onSearch: store.openPicker, onNewSession: store.openNewSession, onQuit: onQuit)
                .contextMenu {
                    Toggle("Launch at login", isOn: Binding(
                        get: { LaunchAtLogin.isEnabled },
                        set: { LaunchAtLogin.set($0) }
                    ))
                    Picker("⌘-click opens", selection: $openTarget) {
                        Text("⌘-click opens Claude Desktop").tag(OpenTarget.desktop.rawValue)
                        Text("⌘-click opens Terminal").tag(OpenTarget.terminal.rawValue)
                    }
                    .pickerStyle(.inline)
                    Button(HookInstaller.isInstalled() ? "Remove Allow / Deny hook…" : "Set up Allow / Deny buttons…") {
                        HookInstaller.confirmAndToggle()
                    }
                    Button("New session…") { store.openNewSession() }
                    Button("Check for updates…") { updates?.checkNow() }
                    Toggle("Check for updates automatically", isOn: $autoUpdates)
                    Button("Shortcuts & tips…") { store.openShortcuts() }
                    Button("Enable double-tap ⌘ shortcut…") { DoubleCommandTap.openAccessibilitySettings() }
                    Button("Quit", action: onQuit)
                }
            if !collapsed {
                Divider().opacity(0.5)
                content
            }
        }
        .frame(minWidth: WidgetMetrics.minWidth, maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
        .overlay(alignment: .leading) { ResizeHandle(edge: .left, resizer: resizer) }
        .overlay(alignment: .trailing) { ResizeHandle(edge: .right, resizer: resizer) }
        .overlay(alignment: .bottom) { if !collapsed { ResizeHandle(edge: .bottom, resizer: resizer) } }
    }

    @ViewBuilder private var content: some View {
        if store.rows.isEmpty {
            Text("No active Claude Code sessions")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: WidgetMetrics.rowHeight)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.rows) { row in
                        SessionRowView(
                            row: row, canHandOff: row.sessionId.map(store.readyForDesktop.contains) ?? false,
                            onDecide: store.decide, onAnswer: store.answer, onRemove: { store.remove(row) },
                            onMarkRead: { store.markRead(row) }, onOpenPopup: { store.openReply(row) }, onHandOff: { store.handOff(row) }
                        )
                        .onTapGesture {
                            if ClickModifiers.current().contains(.command) { store.openPreferred(row) } else { store.openReply(row) }
                        }
                        if row.id != store.rows.last?.id {
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                                .padding(.leading, WidgetMetrics.sidePadding + 26)
                        }
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .onPreferenceChange(ListHeightKey.self) { measuredListHeight = $0 }
            .frame(height: listHeight)
        }
    }
}

struct HeaderIconButton: View {
    let symbol: String
    var hoverColor: Color = Color.primary
    let action: () -> Void

    var body: some View {
        CircleIconButton(symbol: symbol, size: 24, hoverColor: hoverColor, action: action)
    }
}

struct HeaderView: View {
    private static let baseWidthWithTitle: CGFloat = 310
    private static let badgeWidth: CGFloat = 105
    private static let updateIconWidth: CGFloat = 32

    let needsYouCount: Int
    @Binding var collapsed: Bool
    let updateVersion: String?
    let onUpdate: () -> Void
    let onSearch: () -> Void
    let onNewSession: () -> Void
    let onQuit: () -> Void

    private var requiredWidthForTitle: CGFloat {
        Self.baseWidthWithTitle + (needsYouCount > 0 ? Self.badgeWidth : 0) + (updateVersion != nil ? Self.updateIconWidth : 0)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                HeaderIconButton(symbol: collapsed ? "chevron.right" : "chevron.down") { collapsed.toggle() }
                Image(systemName: "asterisk")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(ReplyMetrics.accent)
                if geometry.size.width >= requiredWidthForTitle {
                    Text("Claude Code")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if needsYouCount > 0 {
                    Text("\(needsYouCount) need\(needsYouCount == 1 ? "s" : "") you")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red))
                        .fixedSize()
                        .layoutPriority(1)
                }
                if let updateVersion {
                    HeaderIconButton(symbol: "arrow.down.circle.fill", hoverColor: ReplyMetrics.accent, action: onUpdate)
                        .help("Update to \(updateVersion)")
                }
                HeaderIconButton(symbol: "magnifyingglass", action: onSearch).help("Find an existing session to add")
                HeaderIconButton(symbol: "plus", action: onNewSession).help("New session")
                HeaderIconButton(symbol: "xmark", hoverColor: .red, action: onQuit)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
        }
        .frame(height: WidgetMetrics.headerHeight)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}

struct SessionRowView: View {
    let row: SessionRow
    let canHandOff: Bool
    let onDecide: (PermissionRequest, PermissionDecision) -> Void
    let onAnswer: (PermissionRequest, [String: String]) -> Void
    let onRemove: () -> Void
    let onMarkRead: () -> Void
    let onOpenPopup: () -> Void
    let onHandOff: () -> Void

    @State private var pointerInside = false

    private var hovering: Bool { pointerInside || RowHoverPreview.enabled }
    private var highlighted: Bool { row.state.needsYou || row.state == .unread }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary.frame(height: WidgetMetrics.rowHeight)
            if let request = row.request {
                Group {
                    if request.isQuestion {
                        QuestionCard(request: request, onAnswer: { onAnswer(request, $0) }, onOpen: onOpenPopup)
                    } else {
                        RequestCard(request: request, moreCount: row.requests.count - 1) { decision in
                            onDecide(request, decision)
                        }
                    }
                }
                .padding(.horizontal, WidgetMetrics.sidePadding)
                .padding(.bottom, 14)
            }
        }
        .background(background)
        .overlay(alignment: .leading) {
            if highlighted { Rectangle().fill(row.color).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .onHover { pointerInside = $0 }
    }

    private var background: Color {
        if highlighted { return row.color.opacity(hovering ? 0.16 : 0.10) }
        return hovering ? Color.primary.opacity(0.05) : Color.clear
    }

    private var subtitle: String {
        let label = row.running ? row.state.label : "Not running"
        return row.summary.map { "\(label) · \($0)" } ?? "\(row.folder) · \(label)"
    }

    private var summary: some View {
        HStack(spacing: 12) {
            StatusDot(color: row.color, pulses: row.pulses, halo: highlighted)
                .id("\(row.state.rawValue)-\(row.running)")
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 14, weight: row.state == .unread ? .bold : .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(highlighted ? AnyShapeStyle(row.color) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let agents = row.agents { AgentChip(progress: agents) }
            if canHandOff {
                Button(action: onHandOff) {
                    Label("Desktop", systemImage: "arrow.up.forward.app").lineLimit(1).fixedSize()
                }
                .buttonStyle(PillButtonStyle(tint: StatusPalette.done))
                .help("Ready: open this session in Claude Desktop")
            }
            if hovering {
                HStack(spacing: 6) {
                    if row.state == .unread {
                        Button(action: onMarkRead) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 15))
                        }
                        .buttonStyle(PressScaleStyle())
                        .foregroundStyle(StatusPalette.done)
                        .help("Mark as read")
                    }
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                    }
                    .buttonStyle(PressScaleStyle())
                    .foregroundStyle(.secondary)
                    .help("Remove from widget")
                }
            } else {
                AgeText(since: row.since)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, WidgetMetrics.sidePadding)
    }
}

struct RequestCard: View {
    let request: PermissionRequest
    let moreCount: Int
    let onDecide: (PermissionDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(request.toolDisplayName)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.2)))
                if moreCount > 0 {
                    Text("+\(moreCount) more waiting")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if !request.detail.isEmpty {
                Text(request.detail)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            HStack(spacing: 8) {
                Button("Allow") { onDecide(.allow) }
                    .buttonStyle(ActionButtonStyle(color: .green))
                Button("Deny") { onDecide(.deny) }
                    .buttonStyle(ActionButtonStyle(color: .red))
                Spacer()
            }
        }
    }
}

struct StatusDot: View {
    let color: Color
    let pulses: Bool
    var halo = false
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .background(Circle().fill(color.opacity(halo ? 0.25 : 0)).frame(width: 20, height: 20))
            .frame(width: 20, height: 20)
            .opacity(pulses && dimmed ? 0.4 : 1)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

struct AgeText: View {
    let since: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Text(since.map { Self.compact(from: $0, to: context.date) } ?? "")
        }
    }

    static func compact(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}

struct ResizeHandle: View {
    let edge: ResizeEdge
    let resizer: WidgetResizer

    private let thickness: CGFloat = 8

    var body: some View {
        Color.clear
            .frame(width: edge == .bottom ? nil : thickness, height: edge == .bottom ? thickness : nil)
            .contentShape(Rectangle())
            .background(CursorArea(cursor: cursor))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { _ in resizer.drag(edge) }
                    .onEnded { _ in resizer.end() }
            )
            .padding(edge == .bottom ? .horizontal : .vertical, WidgetMetrics.cornerRadius)
    }

    private var cursor: NSCursor { edge == .bottom ? .resizeUpDown : .resizeLeftRight }
}

struct AgentChip: View {
    let progress: AgentProgress

    private var color: Color { progress.isRunning ? StatusPalette.working : StatusPalette.done }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.2.fill").font(.system(size: 9, weight: .bold))
            Text("\(progress.done)/\(progress.total)").font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.18)))
        .fixedSize()
        .help("\(progress.done) of \(progress.total) sub-agents finished in this turn")
    }
}

struct OptionButton: View {
    let label: String
    let description: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.18 : 0.09)))
        }
        .buttonStyle(PressScaleStyle(lifts: false))
        .help(description)
        .onHover { hovering = $0 }
    }
}

struct QuestionCard: View {
    let request: PermissionRequest
    let onAnswer: ([String: String]) -> Void
    let onOpen: () -> Void

    var body: some View {
        let first = request.questions[0]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if !first.header.isEmpty {
                    Text(first.header)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(StatusPalette.answer.opacity(0.22)))
                }
                if request.questions.count > 1 {
                    Text("+\(request.questions.count - 1) more questions").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Text(first.question).font(.system(size: 13, weight: .semibold)).lineLimit(3)
            if request.canAnswerInline {
                VStack(spacing: 6) {
                    ForEach(Array(first.options.enumerated()), id: \.offset) { _, option in
                        OptionButton(label: option.label, description: option.description) {
                            onAnswer([first.question: option.label])
                        }
                    }
                }
            } else {
                Button("Answer…", action: onOpen).buttonStyle(ActionButtonStyle(color: StatusPalette.answer))
            }
        }
    }
}
