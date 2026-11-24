import SwiftUI

enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(String, level: Int)
    case bullet(String, marker: String)
    case code(String)

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inFence = false

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inFence { blocks.append(.code(code.joined(separator: "\n"))); code = [] } else { flushParagraph() }
                inFence.toggle()
            } else if inFence {
                code.append(line)
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = headingParts(trimmed) {
                flushParagraph()
                blocks.append(.heading(heading.text, level: heading.level))
            } else if let item = bulletParts(trimmed) {
                flushParagraph()
                blocks.append(.bullet(item.text, marker: item.marker))
            } else if trimmed.hasPrefix("|") {
                flushParagraph()
                if case .code(let existing)? = blocks.last, existing.hasPrefix("|") {
                    blocks[blocks.count - 1] = .code(existing + "\n" + trimmed)
                } else {
                    blocks.append(.code(trimmed))
                }
            } else {
                paragraph.append(trimmed)
            }
        }
        if inFence { blocks.append(.code(code.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    private static func headingParts(_ line: String) -> (text: String, level: Int)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces), hashes)
    }

    private static func bulletParts(_ line: String) -> (text: String, marker: String)? {
        if let first = line.first, "-*•".contains(first), line.dropFirst().first == " " {
            return (String(line.dropFirst(2)), "•")
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return (String(line.dropFirst(digits.count + 2)), "\(digits).")
        }
        return nil
    }
}

struct MarkdownText: View, Equatable {
    let text: String
    var size: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.6) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let value):
            Text(Self.inline(value)).font(.system(size: size)).lineSpacing(size * 0.25)
        case .heading(let value, let level):
            Text(Self.inline(value)).font(.system(size: level == 1 ? size + 5 : size + 2, weight: .bold))
        case .bullet(let value, let marker):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).font(.system(size: size)).foregroundStyle(.secondary)
                Text(Self.inline(value)).font(.system(size: size)).lineSpacing(size * 0.25)
            }
        case .code(let value):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(value).font(.system(size: size - 2, design: .monospaced)).fixedSize(horizontal: true, vertical: false)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
        }
    }

    static func inline(_ value: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: value, options: options)) ?? AttributedString(value)
    }
}
