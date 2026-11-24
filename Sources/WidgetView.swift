import AppKit
import SwiftUI

enum HoverPreview {
    static var symbol: String?
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
    let onQuit: () -> Void

    @AppStorage("collapsed") private var collapsed = false
    @AppStorage("widgetMaxHeight") private var maxHeight: Double = 560
    @State private var measuredListHeight: CGFloat = 0

    private var needsYouCount: Int { store.rows.filter { $0.state.needsYou }.count }

    private var listHeight: CGFloat {
        let estimate = CGFloat(store.rows.count) * WidgetMetrics.rowHeight
        let allowed = max(CGFloat(maxHeight) - WidgetMetrics.headerHeight - 1, WidgetMetrics.rowHeight)
        return min(measuredListHeight > 0 ? measuredListHeight : estimate, allowed)
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(needsYouCount: needsYouCount, collapsed: $collapsed, onAdd: store.openPicker, onQuit: onQuit)
                .contextMenu {
                    Toggle("Launch at login", isOn: Binding(
                        get: { LaunchAtLogin.isEnabled },
                        set: { LaunchAtLogin.set($0) }
                    ))
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
                            row: row, onDecide: store.decide, onRemove: { store.remove(row) }
                        )
                        .onTapGesture {
                            if ClickModifiers.current().contains(.command) { store.open(row) } else { store.openReply(row) }
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

    @State private var pointerInside = false

    private var hovering: Bool { pointerInside || HoverPreview.symbol == symbol }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? hoverColor.opacity(0.22) : Color.primary.opacity(0.08)))
                .scaleEffect(hovering ? 1.1 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { pointerInside = $0 }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct HeaderView: View {
    let needsYouCount: Int
    @Binding var collapsed: Bool
    let onAdd: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HeaderIconButton(symbol: collapsed ? "chevron.right" : "chevron.down") { collapsed.toggle() }
            Image(systemName: "asterisk")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(ReplyMetrics.accent)
            Text("Claude Code")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
            HeaderIconButton(symbol: "plus", action: onAdd).help("Add an existing session")
            HeaderIconButton(symbol: "xmark", hoverColor: .red, action: onQuit)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: WidgetMetrics.headerHeight)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}

struct SessionRowView: View {
    let row: SessionRow
    let onDecide: (PermissionRequest, PermissionDecision) -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    private var highlighted: Bool { row.state.needsYou || row.state == .unread }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary.frame(height: WidgetMetrics.rowHeight)
            if let request = row.request {
                RequestCard(request: request, moreCount: row.requests.count - 1) { decision in
                    onDecide(request, decision)
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
        .onHover { hovering = $0 }
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
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove from widget")
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

struct ActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.65 : 0.95)))
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
