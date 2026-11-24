import SwiftUI

extension DesktopSession {
    func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(separator: " ")
        let haystack = "\(title) \(folder)".lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}

enum PickerMetrics {
    static let width: CGFloat = 460
    static let height: CGFloat = 520
}

struct AddSessionView: View {
    @ObservedObject var store: SessionStore
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    private var matches: [DesktopSession] {
        Array(store.candidates.filter { $0.matches(query) }.prefix(60))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add a session").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
            searchField
            Divider().opacity(0.5)
            if matches.isEmpty {
                Text(query.isEmpty ? "No other sessions" : "No sessions match “\(query)”")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches) { session in
                            row(for: session)
                        }
                    }
                }
            }
        }
        .frame(width: PickerMetrics.width, height: PickerMetrics.height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search sessions", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit { if let first = matches.first { add(first) } }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
        .padding(.horizontal, 18).padding(.bottom, 12)
    }

    private func row(for session: DesktopSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            HStack(spacing: 4) {
                Text(session.folder)
                Text("·")
                Text(AgeText.compact(from: session.lastActivity, to: Date()))
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { add(session) }
    }

    private func add(_ session: DesktopSession) {
        store.add(session)
        onClose()
    }
}
