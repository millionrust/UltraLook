import AppKit
import SwiftUI

struct MarkdownPreview: View {
    enum Mode { case preview, raw }

    let file: TextFile
    let blocks: [MarkdownBlock]
    let source: NSAttributedString?
    let baseURL: URL

    @State private var mode: Mode = .preview

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                PillButton(title: "Preview", isOn: mode == .preview) { mode = .preview }
                PillButton(title: "Raw", isOn: mode == .raw) { mode = .raw }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Theme.barBackground)
            .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }

            switch mode {
            case .preview:
                if blocks.isEmpty {
                    MessageView(icon: "doc.richtext", title: "Empty document", detail: "There's nothing to show yet.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                MarkdownBlockView(block: block, depth: 0, baseURL: baseURL)
                            }
                        }
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                }
            case .raw:
                CodeTextView(source: source ?? NSAttributedString(string: file.text), wrap: true)
            }

            if file.isTruncated {
                FooterBar(text: "Showing the first \(Format.bytes(Int64(TextFile.maxBytes))) of this file.")
            }
        }
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let depth: Int
    let baseURL: URL

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(InlineMarkdown.render(text))
                .font(Self.headingFont(level))
                .foregroundStyle(level == 6 ? .secondary : .primary)
                .padding(.top, level <= 2 ? 10 : 4)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Text(InlineMarkdown.render(text))
                .font(.system(size: 13.5))
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)

        case .code(let info, let text):
            CodeBlockView(info: info, text: text)

        case .quote(let blocks):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.quoteBar).frame(width: 3)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
                        MarkdownBlockView(block: child, depth: depth, baseURL: baseURL)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .list(let list):
            ListBlockView(list: list, depth: depth, baseURL: baseURL)

        case .table(let table):
            TableBlockView(table: table)

        case .image(let alt, let source):
            MarkdownImageView(alt: alt, source: source, baseURL: baseURL)

        case .rule:
            Theme.hairline.frame(height: 1).padding(.vertical, 6)
        }
    }

    static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 24, weight: .bold)
        case 2: return .system(size: 19, weight: .semibold)
        case 3: return .system(size: 16, weight: .semibold)
        case 4: return .system(size: 14, weight: .semibold)
        default: return .system(size: 13, weight: .semibold)
        }
    }
}

struct ListBlockView: View {
    let list: MarkdownList
    let depth: Int
    let baseURL: URL

    private static let bullets = ["•", "◦", "▪︎"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(index: index, item: item)
                        .frame(minWidth: list.ordered ? 18 : 10, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, block in
                            MarkdownBlockView(block: block, depth: depth + 1, baseURL: baseURL)
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func marker(index: Int, item: MarkdownList.Item) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 12))
                .foregroundStyle(checked ? Theme.accent : Color.secondary)
        } else if list.ordered {
            Text("\(list.start + index).")
                .font(.system(size: 13.5).monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Text(Self.bullets[depth % Self.bullets.count])
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
        }
    }
}

struct CodeBlockView: View {
    let info: String?
    let text: String

    var body: some View {
        let language = Language.forFence(info)
        ScrollView(.horizontal, showsIndicators: false) {
            Text(SyntaxHighlighter.attributed(text, language: language))
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(3)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.codeBlockBackground))
    }
}

struct TableBlockView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(table.header.indices, id: \.self) { column in
                        cell(table.header[column], column: column, isHeader: true, isLast: table.rows.isEmpty)
                    }
                }
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table.header.indices, id: \.self) { column in
                            cell(table.rows[row][column], column: column, isHeader: false, isLast: row == table.rows.count - 1)
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func cell(_ text: String, column: Int, isHeader: Bool, isLast: Bool) -> some View {
        let alignment: Alignment
        switch table.alignments[column] {
        case .leading: alignment = .leading
        case .center: alignment = .center
        case .trailing: alignment = .trailing
        }
        return Text(InlineMarkdown.render(text))
            .font(.system(size: 12.5, weight: isHeader ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(isHeader ? Theme.barBackground : Color.clear)
            .overlay(alignment: .bottom) { if !isLast { Theme.hairline.frame(height: 1) } }
            .overlay(alignment: .trailing) { if column < table.header.count - 1 { Theme.hairline.frame(width: 1) } }
    }
}

struct MarkdownImageView: View {
    let alt: String
    let source: String
    let baseURL: URL

    @State private var image: NSImage?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: min(image.size.width, 720), alignment: .leading)
            } else if didLoad {
                Label(alt.isEmpty ? (source as NSString).lastPathComponent : alt, systemImage: "photo")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .task(id: source) {
            image = loadLocalImage()
            didLoad = true
        }
    }

    /// Only local, relative images; previews never touch the network.
    private func loadLocalImage() -> NSImage? {
        guard !source.contains("://"), !source.hasPrefix("data:") else { return nil }
        let path = source.removingPercentEncoding ?? source
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : baseURL.appendingPathComponent(path)
        return NSImage(contentsOf: url)
    }
}

enum InlineMarkdown {
    private static let htmlTags = try! NSRegularExpression(
        pattern: #"</?(?:kbd|sup|sub|b|i|em|strong|span|u|small|mark|ins|del|s|abbr|cite|font|a)\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let lineBreaks = try! NSRegularExpression(pattern: #"<br\s*/?>"#, options: [.caseInsensitive])

    static func render(_ text: String) -> AttributedString {
        var cleaned = lineBreaks.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
        cleaned = htmlTags.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: "")

        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var result = (try? AttributedString(markdown: cleaned, options: options)) ?? AttributedString(cleaned)

        let codeRanges = result.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else { return nil }
            return run.range
        }
        for range in codeRanges {
            result[range].font = .system(size: 12, design: .monospaced)
            result[range].backgroundColor = Theme.inlineCodeBackground
        }
        return result
    }
}

extension Language {
    private static let fenceAliases: [String: Language] = [
        "sh": .shell, "bash": .shell, "zsh": .shell, "shell": .shell, "console": .shell, "terminal": .shell,
        "shellsession": .shell, "fish": .shell, "js": .javascript, "javascript": .javascript, "jsx": .javascript,
        "node": .javascript, "ts": .typescript, "typescript": .typescript, "tsx": .typescript, "py": .python,
        "python": .python, "python3": .python, "rb": .ruby, "ruby": .ruby, "yml": .yaml, "yaml": .yaml,
        "objective-c": .objc, "objc": .objc, "c++": .cpp, "cpp": .cpp, "cs": .csharp, "csharp": .csharp,
        "c#": .csharp, "golang": .go, "rs": .rust, "kt": .kotlin, "docker": .dockerfile, "make": .makefile,
        "html": .html, "vue": .html, "svg": .xml, "plist": .xml, "jsonc": .json, "json5": .json, "ps": .powershell,
        "pwsh": .powershell, "tf": .hcl, "terraform": .hcl, "md": .markdown, "patch": .diff, "text": .plainText,
        "plaintext": .plainText, "txt": .plainText,
    ]

    static func forFence(_ info: String?) -> Language {
        guard let word = info?.split(whereSeparator: { $0 == " " || $0 == "{" || $0 == "," }).first?.lowercased() else {
            return .plainText
        }
        if let alias = fenceAliases[word] { return alias }
        if let language = all.first(where: { $0.id == word }) { return language }
        return byExtension[word] ?? .plainText
    }
}

extension SyntaxHighlighter {
    /// SwiftUI flavor of `highlight`, for code blocks inside rendered markdown.
    static func attributed(_ text: String, language: Language) -> AttributedString {
        var result = AttributedString(text)
        for token in tokens(in: text, language: language) {
            guard let range = Range(token.range, in: result) else { continue }
            result[range].foregroundColor = Color(nsColor: CodeTheme.color(for: token.kind))
        }
        return result
    }
}
