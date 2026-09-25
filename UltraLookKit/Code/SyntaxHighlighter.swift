import AppKit

public struct Token: Equatable {
    public let range: NSRange
    public let kind: TokenKind
}

public enum SyntaxHighlighter {
    /// Above this size files are shown without colors so previews stay instant.
    public static let maxHighlightedLength = 512 * 1024

    private static let cacheLock = NSLock()
    private static var cache: [String: NSRegularExpression] = [:]

    static func regex(for language: Language) -> NSRegularExpression? {
        guard !language.rules.isEmpty else { return nil }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[language.id] { return cached }
        let pattern = language.rules.map { "(\($0.pattern))" }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            assertionFailure("Invalid pattern for \(language.id)")
            return nil
        }
        assert(regex.numberOfCaptureGroups == language.rules.count, "\(language.id) rule has a capturing group")
        cache[language.id] = regex
        return regex
    }

    public static func tokens(in text: String, language: Language) -> [Token] {
        let ns = text as NSString
        guard ns.length <= maxHighlightedLength, let regex = regex(for: language) else { return [] }
        let rules = language.rules
        var tokens: [Token] = []
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.range.length > 0 else { return }
            for index in 0..<rules.count where match.range(at: index + 1).location != NSNotFound {
                tokens.append(Token(range: match.range, kind: rules[index].kind))
                break
            }
        }
        return tokens
    }

    public static func highlight(_ text: String, language: Language, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: CodeTheme.text,
        ])
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        result.beginEditing()
        for token in tokens(in: text, language: language) {
            result.addAttribute(.foregroundColor, value: CodeTheme.color(for: token.kind), range: token.range)
            switch token.kind {
            case .heading:
                result.addAttribute(.font, value: bold, range: token.range)
            case .emphasis:
                result.addAttribute(.font, value: italic, range: token.range)
            default:
                break
            }
        }
        result.endEditing()
        return result
    }
}

public enum CodeTheme {
    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    public static let text = dynamic(light: 0x1F1F24, dark: 0xDFDFE0)
    public static let lineNumber = dynamic(light: 0xA3A3A8, dark: 0x6C6C72)
    public static let gutterBackground = dynamic(light: 0xFAFAFA, dark: 0x1E1E20)
    public static let gutterBorder = dynamic(light: 0xECECEE, dark: 0x2C2C30)

    public static func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .comment: return comment
        case .string: return string
        case .number, .literal: return number
        case .keyword: return keyword
        case .type: return type
        case .attribute: return attribute
        case .function: return function
        case .meta: return meta
        case .tag: return tag
        case .attributeName: return attributeName
        case .variable: return variable
        case .heading: return heading
        case .link: return link
        case .emphasis: return text
        case .inserted: return inserted
        case .deleted: return deleted
        }
    }

    // Tuned after Xcode's default light/dark themes.
    static let comment = dynamic(light: 0x707F8C, dark: 0x7F8C98)
    static let string = dynamic(light: 0xC41A16, dark: 0xFC6A5D)
    static let number = dynamic(light: 0x1C00CF, dark: 0xD0BF69)
    static let keyword = dynamic(light: 0x9B2393, dark: 0xFC5FA3)
    static let type = dynamic(light: 0x0B4F79, dark: 0x5DD8FF)
    static let attribute = dynamic(light: 0x815F03, dark: 0xFD8F3F)
    static let function = dynamic(light: 0x326D74, dark: 0x67B7A4)
    static let meta = dynamic(light: 0x643820, dark: 0xFD8F3F)
    static let tag = dynamic(light: 0x0F68A0, dark: 0x6BDFFF)
    static let attributeName = dynamic(light: 0x6C36A9, dark: 0xA167E6)
    static let variable = dynamic(light: 0x3E8087, dark: 0x9EF1DD)
    static let heading = dynamic(light: 0x1F1F24, dark: 0xFFFFFF)
    static let link = dynamic(light: 0x0E0EFF, dark: 0x6699FF)
    static let inserted = dynamic(light: 0x1E7A34, dark: 0x6BD68A)
    static let deleted = dynamic(light: 0xB42318, dark: 0xFF7B72)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
