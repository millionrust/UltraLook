import Foundation

public indirect enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(info: String?, text: String)
    case quote([MarkdownBlock])
    case list(MarkdownList)
    case table(MarkdownTable)
    case image(alt: String, source: String)
    case rule
}

public struct MarkdownList: Equatable {
    public struct Item: Equatable {
        /// nil for a normal item, true/false for `- [x]` / `- [ ]`.
        public var checked: Bool?
        public var blocks: [MarkdownBlock]
    }

    public var ordered: Bool
    public var start: Int
    public var items: [Item]
}

public struct MarkdownTable: Equatable {
    public enum Alignment: Equatable { case leading, center, trailing }
    public var header: [String]
    public var alignments: [Alignment]
    public var rows: [[String]]
}

/// A small block-level CommonMark/GFM parser. Inline syntax is left as text
/// and rendered later with `AttributedString(markdown:)`.
public enum MarkdownParser {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\t", with: "    ")
        var lines = normalized.components(separatedBy: "\n")
        lines = stripFrontMatter(lines)
        return parseBlocks(lines[...])
    }

    // MARK: Block loop

    static func parseBlocks(_ lines: ArraySlice<String>) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = lines.startIndex

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(contentsOf: paragraphBlocks(paragraph))
            paragraph.removeAll()
        }

        while i < lines.endIndex {
            let line = lines[i]
            let indent = indentation(line)
            let body = line.trimmingCharacters(in: .whitespaces)

            if body.isEmpty {
                flush()
                i += 1
                continue
            }

            // Indented code only starts outside a paragraph.
            if indent >= 4, paragraph.isEmpty {
                var code: [String] = []
                while i < lines.endIndex, isBlank(lines[i]) || indentation(lines[i]) >= 4 {
                    code.append(isBlank(lines[i]) ? "" : String(lines[i].dropFirst(4)))
                    i += 1
                }
                while code.last == "" { code.removeLast() }
                blocks.append(.code(info: nil, text: code.joined(separator: "\n")))
                continue
            }

            if indent < 4, let fence = fenceOpening(body) {
                flush()
                i += 1
                var code: [String] = []
                while i < lines.endIndex {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence.marker), candidate.allSatisfy({ $0 == fence.marker.first }) {
                        i += 1
                        break
                    }
                    code.append(removeIndent(lines[i], upTo: indent))
                    i += 1
                }
                blocks.append(.code(info: fence.info, text: code.joined(separator: "\n")))
                continue
            }

            if indent < 4, let heading = atxHeading(body) {
                flush()
                blocks.append(heading)
                i += 1
                continue
            }

            if indent < 4, !paragraph.isEmpty, let level = setextLevel(body) {
                let text = paragraph.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                paragraph.removeAll()
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            if indent < 4, isThematicBreak(body) {
                flush()
                blocks.append(.rule)
                i += 1
                continue
            }

            if indent < 4, body.hasPrefix(">") {
                flush()
                var inner: [String] = []
                while i < lines.endIndex {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix(">") {
                        var rest = l.dropFirst()
                        if rest.first == " " { rest = rest.dropFirst() }
                        inner.append(String(rest))
                    } else if !l.isEmpty, !(inner.last ?? "").trimmingCharacters(in: .whitespaces).isEmpty, !startsBlock(l) {
                        inner.append(l) // lazy continuation
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.quote(parseBlocks(inner[...])))
                continue
            }

            if indent < 4, let marker = listMarker(line), paragraph.isEmpty || marker.canInterruptParagraph {
                flush()
                let (list, next) = parseList(lines, from: i, first: marker)
                blocks.append(.list(list))
                i = next
                continue
            }

            if indent < 4, body.contains("|"), i + 1 < lines.endIndex,
               let alignments = tableDelimiter(lines[i + 1]) {
                let header = tableCells(body)
                if header.count == alignments.count {
                    flush()
                    i += 2
                    var rows: [[String]] = []
                    while i < lines.endIndex {
                        let row = lines[i].trimmingCharacters(in: .whitespaces)
                        guard !row.isEmpty, row.contains("|") || !startsBlock(row) else { break }
                        var cells = tableCells(row)
                        cells = Array(cells.prefix(header.count)) + Array(repeating: "", count: max(0, header.count - cells.count))
                        rows.append(cells)
                        i += 1
                    }
                    blocks.append(.table(MarkdownTable(header: header, alignments: alignments, rows: rows)))
                    continue
                }
            }

            if indent < 4, paragraph.isEmpty, body.hasPrefix("<!--") {
                while i < lines.endIndex, !lines[i].contains("-->") { i += 1 }
                i += 1
                continue
            }

            if indent < 4, paragraph.isEmpty, isHTMLBlockStart(body) {
                var html: [String] = []
                while i < lines.endIndex, !isBlank(lines[i]) {
                    html.append(lines[i])
                    i += 1
                }
                blocks.append(contentsOf: htmlBlocks(html.joined(separator: "\n")))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flush()
        return blocks
    }

    // MARK: Lists

    struct ListMarker {
        var indent: Int
        var ordered: Bool
        var number: Int
        var delimiter: Character
        var contentIndent: Int
        var content: String

        var canInterruptParagraph: Bool { !content.isEmpty && (!ordered || number == 1) }
    }

    static func listMarker(_ line: String) -> ListMarker? {
        let indent = indentation(line)
        let rest = line.dropFirst(indent)
        guard let first = rest.first else { return nil }

        var ordered = false
        var number = 1
        var delimiter: Character = first
        var markerLength = 1

        if "-*+".contains(first) {
            if isThematicBreak(String(rest)) { return nil }
        } else if first.isNumber {
            let digits = rest.prefix { $0.isNumber }
            guard digits.count <= 9, let d = rest.dropFirst(digits.count).first, d == "." || d == ")" else { return nil }
            ordered = true
            number = Int(digits) ?? 1
            delimiter = d
            markerLength = digits.count + 1
        } else {
            return nil
        }

        let afterMarker = rest.dropFirst(markerLength)
        let spaces = afterMarker.prefix { $0 == " " }.count
        guard spaces > 0 || afterMarker.isEmpty else { return nil }
        let padding = spaces > 4 ? 1 : max(1, spaces)
        let content = String(afterMarker.dropFirst(min(spaces, padding)))
        return ListMarker(indent: indent, ordered: ordered, number: number, delimiter: delimiter,
                          contentIndent: indent + markerLength + padding, content: content)
    }

    static func parseList(_ lines: ArraySlice<String>, from start: Int, first: ListMarker) -> (MarkdownList, Int) {
        var itemsLines: [[String]] = []
        var current = [first.content]
        var contentIndent = first.contentIndent
        var i = start + 1

        func isSibling(_ marker: ListMarker) -> Bool {
            marker.ordered == first.ordered && marker.delimiter == first.delimiter && marker.indent < contentIndent
        }

        while i < lines.endIndex {
            let line = lines[i]
            if isBlank(line) {
                var j = i
                while j < lines.endIndex, isBlank(lines[j]) { j += 1 }
                guard j < lines.endIndex else { break }
                if indentation(lines[j]) >= contentIndent {
                    current.append(contentsOf: Array(repeating: "", count: j - i))
                    i = j
                    continue
                }
                if let marker = listMarker(lines[j]), isSibling(marker) {
                    i = j
                    continue
                }
                break
            }

            if indentation(line) >= contentIndent {
                current.append(removeIndent(line, upTo: contentIndent))
                i += 1
                continue
            }

            if let marker = listMarker(line) {
                guard isSibling(marker) else { break }
                itemsLines.append(current)
                current = [marker.content]
                contentIndent = marker.contentIndent
                i += 1
                continue
            }

            let body = line.trimmingCharacters(in: .whitespaces)
            if startsBlock(body) || isBlank(lines[i - 1]) { break }
            current.append(body) // lazy paragraph continuation
            i += 1
        }
        itemsLines.append(current)

        let items = itemsLines.map { lines -> MarkdownList.Item in
            var lines = lines
            var checked: Bool?
            if let firstLine = lines.first {
                let lower = firstLine.lowercased()
                if lower.hasPrefix("[ ] ") || lower == "[ ]" {
                    checked = false
                    lines[0] = String(firstLine.dropFirst(min(4, firstLine.count)))
                } else if lower.hasPrefix("[x] ") || lower == "[x]" {
                    checked = true
                    lines[0] = String(firstLine.dropFirst(min(4, firstLine.count)))
                }
            }
            return MarkdownList.Item(checked: checked, blocks: parseBlocks(lines[...]))
        }
        return (MarkdownList(ordered: first.ordered, start: first.number, items: items), i)
    }

    // MARK: Leaf helpers

    static func fenceOpening(_ body: String) -> (marker: String, info: String?)? {
        guard let c = body.first, c == "`" || c == "~" else { return nil }
        let run = body.prefix { $0 == c }
        guard run.count >= 3 else { return nil }
        let info = body.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
        if c == "`", info.contains("`") { return nil }
        return (String(run), info.isEmpty ? nil : info)
    }

    static func atxHeading(_ body: String) -> MarkdownBlock? {
        let hashes = body.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = body.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // Optional closing sequence: "## Title ##"
        if let range = text.range(of: #"\s+#+$"#, options: .regularExpression) {
            text.removeSubrange(range)
        } else if text.allSatisfy({ $0 == "#" }) {
            text = ""
        }
        return .heading(level: hashes, text: text)
    }

    static func setextLevel(_ body: String) -> Int? {
        if body.allSatisfy({ $0 == "=" }) { return 1 }
        if body.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    static func isThematicBreak(_ body: String) -> Bool {
        let chars = body.filter { $0 != " " }
        guard chars.count >= 3, let c = chars.first, "-*_".contains(c) else { return false }
        return chars.allSatisfy { $0 == c }
    }

    static func tableDelimiter(_ line: String) -> [MarkdownTable.Alignment]? {
        let body = line.trimmingCharacters(in: .whitespaces)
        guard body.contains("-"), body.allSatisfy({ "|:- ".contains($0) }) else { return nil }
        let cells = tableCells(body)
        guard !cells.isEmpty else { return nil }
        var alignments: [MarkdownTable.Alignment] = []
        for cell in cells {
            guard cell.contains("-") else { return nil }
            let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
            alignments.append(left && right ? .center : right ? .trailing : .leading)
        }
        return alignments
    }

    static func tableCells(_ row: String) -> [String] {
        var body = Substring(row.trimmingCharacters(in: .whitespaces))
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|"), !body.hasSuffix("\\|") { body = body.dropLast() }

        var cells: [String] = []
        var cell = ""
        var inCode = false
        var escaped = false
        for ch in body {
            if escaped {
                if ch != "|" { cell.append("\\") }
                cell.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "`" {
                inCode.toggle()
                cell.append(ch)
            } else if ch == "|", !inCode {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(ch)
            }
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    static func paragraphBlocks(_ lines: [String]) -> [MarkdownBlock] {
        let text = joinParagraph(lines)
        if let image = standaloneImage(text) { return [image] }
        return [.paragraph(text)]
    }

    /// Soft line breaks become spaces; two trailing spaces or a backslash force a break.
    static func joinParagraph(_ lines: [String]) -> String {
        var result = ""
        for (index, raw) in lines.enumerated() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            let isLast = index == lines.count - 1
            if isLast {
                result += line
                break
            }
            if raw.hasSuffix("  ") {
                result += line + "\n"
            } else if line.hasSuffix("\\") {
                line.removeLast()
                result += line + "\n"
            } else {
                result += line + " "
            }
        }
        return result
    }

    static let imagePattern = try! NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)$"#)

    static func standaloneImage(_ text: String) -> MarkdownBlock? {
        let ns = text as NSString
        guard let match = imagePattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return .image(alt: ns.substring(with: match.range(at: 1)), source: ns.substring(with: match.range(at: 2)))
    }

    static let htmlTagNames: Set<String> = [
        "p", "div", "img", "a", "h1", "h2", "h3", "h4", "h5", "h6", "picture", "source", "br", "hr",
        "table", "tr", "td", "th", "thead", "tbody", "details", "summary", "center", "span", "b", "i",
        "strong", "em", "sub", "sup", "kbd", "ul", "ol", "li", "pre", "code", "section", "figure",
        "figcaption", "blockquote", "video", "svg", "nav", "header", "footer", "small", "u", "dl", "dt", "dd",
    ]

    static func isHTMLBlockStart(_ body: String) -> Bool {
        guard body.hasPrefix("<") else { return false }
        let name = body.dropFirst().drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
        return htmlTagNames.contains(name)
    }

    static let imgTag = try! NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive])
    static let attribute = try! NSRegularExpression(pattern: #"\b(src|alt)\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive])

    /// README headers are often raw HTML. Keep what's readable: images and text.
    static func htmlBlocks(_ html: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let ns = html as NSString
        for match in imgTag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            var src = "", alt = ""
            for attr in attribute.matches(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) {
                let key = (tag as NSString).substring(with: attr.range(at: 1)).lowercased()
                let valueRange = attr.range(at: 2).location != NSNotFound ? attr.range(at: 2) : attr.range(at: 3)
                let value = (tag as NSString).substring(with: valueRange)
                if key == "src" { src = value } else { alt = value }
            }
            if !src.isEmpty { blocks.append(.image(alt: alt, source: src)) }
        }
        let text = stripTags(html)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !text.isEmpty { blocks.append(.paragraph(text)) }
        return blocks
    }

    static let tagPattern = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->|</?[A-Za-z][^>]*>"#)

    static func stripTags(_ html: String) -> String {
        let ns = html as NSString
        let withBreaks = tagPattern.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: ns.length), withTemplate: "\n")
        return withBreaks
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    static func startsBlock(_ body: String) -> Bool {
        body.hasPrefix("#") || body.hasPrefix(">") || body.hasPrefix("```") || body.hasPrefix("~~~")
            || isThematicBreak(body) || listMarker(body) != nil
    }

    static func stripFrontMatter(_ lines: [String]) -> [String] {
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else {
            return lines
        }
        // Only treat it as front matter if it looks like YAML keys.
        let body = lines[1..<end]
        guard body.contains(where: { $0.contains(":") }) else { return lines }
        return Array(lines[(end + 1)...])
    }

    static func indentation(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " }
    }

    static func removeIndent(_ line: String, upTo count: Int) -> String {
        String(line.dropFirst(min(count, indentation(line))))
    }
}
