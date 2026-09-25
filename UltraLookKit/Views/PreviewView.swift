import AppKit
import SwiftUI

/// A document plus everything expensive (highlighting, markdown parsing)
/// computed up front, so the view appears fully formed.
public struct LoadedPreview {
    public let document: PreviewDocument
    let source: NSAttributedString?
    let blocks: [MarkdownBlock]

    public static func prepare(url: URL) throws -> LoadedPreview {
        let document = try PreviewDocument.load(from: url)
        switch document.content {
        case .markdown(let file):
            return LoadedPreview(
                document: document,
                source: CodeStyle.attributed(file.text, language: .markdown),
                blocks: MarkdownParser.parse(file.text)
            )
        case .code(let file, let language):
            return LoadedPreview(document: document, source: CodeStyle.attributed(file.text, language: language), blocks: [])
        case .archive, .binary:
            return LoadedPreview(document: document, source: nil, blocks: [])
        }
    }
}

enum CodeStyle {
    static func paragraphStyle(font: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        style.defaultTabInterval = spaceWidth * 4
        style.tabStops = []
        style.lineSpacing = Theme.codeLineSpacing
        return style
    }

    static func attributed(_ text: String, language: Language) -> NSAttributedString {
        let font = Theme.codeFont
        let result = NSMutableAttributedString(attributedString: SyntaxHighlighter.highlight(text, language: language, font: font))
        result.addAttribute(.paragraphStyle, value: paragraphStyle(font: font), range: NSRange(location: 0, length: result.length))
        return result
    }
}

/// Root view shared by the Quick Look extension and the host app.
public struct PreviewView: View {
    let preview: LoadedPreview

    public init(preview: LoadedPreview) {
        self.preview = preview
    }

    public var body: some View {
        let document = preview.document
        VStack(spacing: 0) {
            HeaderView(document: document)
            content(document)
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private func content(_ document: PreviewDocument) -> some View {
        switch document.content {
        case .markdown(let file):
            MarkdownPreview(file: file, blocks: preview.blocks, source: preview.source, baseURL: document.url.deletingLastPathComponent())
        case .code(let file, _):
            CodePreview(file: file, source: preview.source ?? NSAttributedString(string: file.text))
        case .archive(let listing):
            ArchivePreview(listing: listing)
        case .binary:
            MessageView(icon: "doc", title: "No text preview", detail: "This file contains binary data.")
        }
    }
}

struct HeaderView: View {
    let document: PreviewDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.iconTile))
            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(document.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(document.badge)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .overlay(Capsule().strokeBorder(Theme.badgeBorder, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
        .textSelection(.enabled)
    }

    private var icon: String {
        switch document.content {
        case .markdown: return "doc.richtext"
        case .code(_, let language): return language.isPlainText ? "doc.text" : "chevron.left.forwardslash.chevron.right"
        case .archive: return "doc.zipper"
        case .binary: return "doc"
        }
    }
}

public struct MessageView: View {
    let icon: String
    let title: String
    let detail: String

    public init(icon: String, title: String, detail: String) {
        self.icon = icon
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Footer line used for counts and truncation notices.
struct FooterBar: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(Theme.barBackground)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
    }
}
