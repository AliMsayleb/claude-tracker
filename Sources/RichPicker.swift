import SwiftUI

struct PickerOption: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
}

struct PickerAction {
    let symbol: String
    let title: String
    let perform: () -> Void
}

struct RichPicker: View {
    let current: PickerOption
    let options: [PickerOption]
    var action: PickerAction?
    var arrowEdge: Edge = .top
    var popoverWidth: CGFloat = 440
    var maxListHeight: CGFloat = 440
    var detailLines: Int? = nil
    let onSelect: (String) -> Void

    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            card(current, trailing: AnyView(chevron))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.07)))
                .hoverHighlight(cornerRadius: 12, opacity: 0.08)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: arrowEdge) { list }
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
    }

    var popoverContent: some View { list }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(options) { option in
                    Button {
                        onSelect(option.id)
                        open = false
                    } label: {
                        card(option, trailing: AnyView(option.id == current.id ? AnyView(check) : AnyView(EmptyView())))
                            .hoverHighlight(cornerRadius: 10, opacity: 0.10)
                    }
                    .buttonStyle(.plain)
                }
                if let action {
                    Divider().padding(.vertical, 4)
                    Button {
                        open = false
                        action.perform()
                    } label: {
                        card(PickerOption(id: "action", symbol: action.symbol, title: action.title, detail: ""), trailing: AnyView(EmptyView()))
                            .hoverHighlight(cornerRadius: 10, opacity: 0.10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: popoverWidth)
        .frame(maxHeight: maxListHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var check: some View {
        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(ReplyMetrics.accent)
    }

    private func card(_ option: PickerOption, trailing: AnyView) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: option.symbol).foregroundStyle(ReplyMetrics.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if !option.detail.isEmpty {
                    Text(option.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(detailLines)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
