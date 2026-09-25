import Foundation

/// A decoded text file, capped at `maxBytes` so huge logs stay responsive.
public struct TextFile {
    public static let maxBytes = 4 * 1024 * 1024

    public let text: String
    public let encodingName: String
    public let lineCount: Int
    /// True when only the first `maxBytes` of the file were read.
    public let isTruncated: Bool

    public var wordCount: Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    public init(text: String, encodingName: String, isTruncated: Bool = false) {
        self.text = text
        self.encodingName = encodingName
        self.isTruncated = isTruncated
        self.lineCount = TextFile.countLines(text)
    }

    /// Returns nil when the file looks binary.
    public static func load(url: URL) throws -> TextFile? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        let truncated = data.count > maxBytes
        if !truncated, data.starts(with: Array("bplist".utf8)), let xml = xmlPropertyList(from: data) {
            return TextFile(text: xml, encodingName: "Binary plist")
        }
        return decode(truncated ? data.prefix(maxBytes) : data, isTruncated: truncated)
    }

    public static func decode(_ data: Data, isTruncated: Bool = false) -> TextFile? {
        let bytes = [UInt8](data)

        if bytes.starts(with: [0xEF, 0xBB, 0xBF]),
           let s = String(bytes: bytes.dropFirst(3), encoding: .utf8) {
            return TextFile(text: s, encodingName: "UTF-8", isTruncated: isTruncated)
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]),
           let s = String(data: data, encoding: .utf16) {
            return TextFile(text: s, encodingName: "UTF-16", isTruncated: isTruncated)
        }
        if bytes.prefix(8192).contains(0) { return nil }

        if let s = decodeUTF8(bytes, allowTrailingCut: isTruncated) {
            return TextFile(text: s, encodingName: bytes.allSatisfy { $0 < 0x80 } ? "ASCII" : "UTF-8", isTruncated: isTruncated)
        }
        if let s = String(data: data, encoding: .windowsCP1252) {
            return TextFile(text: s, encodingName: "Windows Latin 1", isTruncated: isTruncated)
        }
        return String(data: data, encoding: .isoLatin1).map {
            TextFile(text: $0, encodingName: "ISO Latin 1", isTruncated: isTruncated)
        }
    }

    /// Binary property lists are shown as their XML equivalent.
    static func xmlPropertyList(from data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let xml = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return nil
        }
        return String(data: xml, encoding: .utf8)
    }

    /// A truncated read may split a multi-byte character; drop up to 3 trailing bytes to recover.
    private static func decodeUTF8(_ bytes: [UInt8], allowTrailingCut: Bool) -> String? {
        let attempts = allowTrailingCut ? 0...3 : 0...0
        for cut in attempts where bytes.count >= cut {
            if let s = String(bytes: bytes.dropLast(cut), encoding: .utf8) { return s }
        }
        return nil
    }

    static func countLines(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        var lines = 1
        for byte in text.utf8 where byte == 0x0A { lines += 1 }
        if text.utf8.last == 0x0A { lines -= 1 }
        return lines
    }
}
