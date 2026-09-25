import Foundation
import UniformTypeIdentifiers

/// Everything a preview needs, loaded off the main thread from a file URL.
public struct PreviewDocument {
    public enum Content {
        case markdown(TextFile)
        case code(TextFile, Language)
        case archive(ArchiveListing)
        case binary
    }

    public let url: URL
    public let fileSize: Int64
    public let content: Content

    public var name: String { url.lastPathComponent }

    public init(url: URL, fileSize: Int64, content: Content) {
        self.url = url
        self.fileSize = fileSize
        self.content = content
    }

    /// Short uppercase label shown in the header badge.
    public var badge: String {
        switch content {
        case .markdown: return "MARKDOWN"
        case .code(_, let language): return language.isPlainText ? "TEXT" : "CODE"
        case .archive(let listing): return "\(listing.format.displayName.uppercased()) ARCHIVE"
        case .binary: return "BINARY"
        }
    }

    /// Metadata line under the file name, e.g. "819 bytes · UTF-8 · 23 lines".
    public var subtitle: String {
        var parts = [Format.bytes(fileSize)]
        switch content {
        case .markdown(let file):
            parts.append("Markdown document")
            parts.append(Format.count(file.wordCount, "word"))
        case .code(let file, let language):
            parts.append(file.encodingName)
            if !language.isPlainText { parts.append(language.name) }
            parts.append(Format.count(file.lineCount, "line"))
        case .archive(let listing):
            parts.append(Format.count(listing.fileCount, "file"))
            parts.append("\(Format.bytes(listing.expandedSize)) expanded")
        case .binary:
            parts.append("Binary data")
        }
        return parts.joined(separator: " · ")
    }
}

extension PreviewDocument {
    /// Reads and classifies the file. Safe to call from any thread.
    public static func load(from url: URL) throws -> PreviewDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values.isDirectory == true {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "Folders can't be previewed."])
        }
        let size = Int64(values.fileSize ?? 0)
        let kind = FileKind.detect(url: url)

        switch kind {
        case .archive(let format):
            let listing = try ArchiveReader.read(url: url, format: format)
            return PreviewDocument(url: url, fileSize: size, content: .archive(listing))
        case .markdown:
            let file = try TextFile.load(url: url)
            return PreviewDocument(url: url, fileSize: size, content: file.map { .markdown($0) } ?? .binary)
        case .code(let language):
            let file = try TextFile.load(url: url)
            return PreviewDocument(url: url, fileSize: size, content: file.map { .code($0, language) } ?? .binary)
        }
    }
}

enum FileKind {
    case markdown
    case code(Language)
    case archive(ArchiveFormat)

    static func detect(url: URL) -> FileKind {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if name.hasSuffix(".tar.gz") || ext == "tgz" { return .archive(.tarGzip) }
        if let format = ArchiveFormat.sniff(url: url) { return .archive(format) }
        if Language.markdownExtensions.contains(ext) { return .markdown }
        return .code(Language.detect(fileName: url.lastPathComponent))
    }
}

enum Format {
    static func bytes(_ count: Int64) -> String {
        if count < 1024 { return count == 1 ? "1 byte" : "\(count) bytes" }
        return ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func count(_ n: Int, _ noun: String) -> String {
        let number = NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
        return "\(number) \(noun)\(n == 1 ? "" : "s")"
    }
}
