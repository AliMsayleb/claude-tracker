import SwiftUI

enum HoverPreview {
    static var symbol: String?
    static var forceAll = false
}

struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double
    let tint: Color

    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(inside || HoverPreview.forceAll ? opacity : 0))
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.12), value: inside)
            .onHover { inside = $0 }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 10, opacity: Double = 0.10, tint: Color = .primary) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, opacity: opacity, tint: tint))
    }
}

struct PressScaleStyle: ButtonStyle {
    var lifts = true

    func makeBody(configuration: Configuration) -> some View {
        PressScaleBody(configuration: configuration, lifts: lifts)
    }
}

private struct PressScaleBody: View {
    let configuration: ButtonStyleConfiguration
    let lifts: Bool

    @State private var inside = false

    private var hovering: Bool { lifts && (inside || HoverPreview.forceAll) }

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : (hovering ? 1.05 : 1))
            .brightness(hovering ? 0.08 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { inside = $0 }
    }
}

struct ActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, color: color)
    }
}

private struct ActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color

    @State private var inside = false

    private var hovering: Bool { inside || HoverPreview.forceAll }

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.65 : (hovering ? 1 : 0.88))))
            .scaleEffect(configuration.isPressed ? 0.96 : (hovering ? 1.03 : 1))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { inside = $0 }
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, tint: tint)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color

    @State private var inside = false

    private var hovering: Bool { inside || HoverPreview.forceAll }

    var body: some View {
        configuration.label
            .foregroundStyle(tint == .primary ? Color.primary : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.35 : (hovering ? 0.28 : 0.14))))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { inside = $0 }
    }
}

struct CircleIconButton: View {
    let symbol: String
    var size: CGFloat = 28
    var hoverColor: Color = .primary
    let action: () -> Void

    @State private var inside = false

    private var hovering: Bool { inside || HoverPreview.symbol == symbol || HoverPreview.forceAll }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? hoverColor.opacity(0.22) : Color.primary.opacity(0.08)))
                .scaleEffect(hovering ? 1.1 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(PressScaleStyle(lifts: false))
        .onHover { inside = $0 }
    }
}
