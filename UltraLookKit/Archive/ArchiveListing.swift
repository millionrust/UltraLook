import Foundation
import UniformTypeIdentifiers

public enum ArchiveFormat: Equatable {
    case zip, tar, tarGzip

    public var displayName: String {
        switch self {
        case .zip: return "Zip"
        case .tar: return "Tar"
        case .tarGzip: return "Tar.gz"
        }
    }

    /// Detects the format from the file's first bytes, so misnamed archives still work.
    static func sniff(url: URL) -> ArchiveFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 512), head.count >= 4 else { return nil }
        let b = [UInt8](head)
        if b[0] == 0x50, b[1] == 0x4B, (b[2] == 0x03 && b[3] == 0x04) || (b[2] == 0x05 && b[3] == 0x06) {
            return .zip
        }
        if b[0] == 0x1F, b[1] == 0x8B {
            // A plain .gz of a single text file isn't an archive; only claim tarballs.
            let ext = url.pathExtension.lowercased()
            return ext == "tgz" || url.lastPathComponent.lowercased().hasSuffix(".tar.gz") ? .tarGzip : nil
        }
        if b.count >= 262, String(bytes: b[257..<262], encoding: .ascii) == "ustar" {
            return .tar
        }
        return nil
    }
}

public struct ArchiveEntry: Equatable {
    public var path: String
    public var isDirectory: Bool
    public var size: Int64
    public var compressedSize: Int64?
    public var modified: Date?
    public var isEncrypted: Bool = false
    public var isSymlink: Bool = false
}

/// A folder tree built from the archive's flat entry list.
public final class ArchiveNode: Identifiable {
    public let id: String
    public let name: String
    public let isDirectory: Bool
    public private(set) var size: Int64
    public let modified: Date?
    public let isEncrypted: Bool
    public private(set) var children: [ArchiveNode] = []
    fileprivate var childIndex: [String: ArchiveNode] = [:]

    init(id: String, name: String, isDirectory: Bool, size: Int64 = 0, modified: Date? = nil, isEncrypted: Bool = false) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.isEncrypted = isEncrypted
    }

    public var kind: String {
        if isDirectory { return "Folder" }
        let ext = (name as NSString).pathExtension
        let type = ext.isEmpty ? nil : UTType(filenameExtension: ext)
        // Prefer our language name when macOS maps the extension to something non-textual (".ts" is video).
        let language = Language.detect(fileName: name)
        if !language.isPlainText, type.map({ !$0.conforms(to: .text) || $0.isDynamic }) ?? true {
            return "\(language.name) source"
        }
        if let type, !type.isDynamic, let description = type.localizedDescription {
            return description.prefix(1).uppercased() + description.dropFirst()
        }
        return ext.isEmpty ? "Document" : "\(ext.uppercased()) file"
    }

    fileprivate func child(named name: String, path: String) -> ArchiveNode {
        if let existing = childIndex[name] { return existing }
        let node = ArchiveNode(id: path, name: name, isDirectory: true)
        add(node)
        return node
    }

    fileprivate func add(_ node: ArchiveNode) {
        if let existing = childIndex[node.name] {
            // A later entry for the same path wins (tar appends updates).
            children.removeAll { $0 === existing }
        }
        childIndex[node.name] = node
        children.append(node)
    }

    fileprivate func finish() -> (files: Int, folders: Int) {
        var files = 0, folders = 0
        if isDirectory {
            size = 0
            for child in children {
                let counts = child.finish()
                files += counts.files
                folders += counts.folders
                size += child.size
                if child.isDirectory { folders += 1 } else { files += 1 }
            }
            children.sort {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            childIndex = [:]
        }
        return (files, folders)
    }
}

public struct ArchiveListing {
    public let format: ArchiveFormat
    public let root: ArchiveNode
    public let fileCount: Int
    public let folderCount: Int
    public let expandedSize: Int64
    public let isEncrypted: Bool
    /// Set when the listing was cut short (entry limit or a damaged archive).
    public let note: String?

    static let hiddenPrefixes = ["__MACOSX/"]
    static let hiddenNames: Set<String> = [".DS_Store"]

    public init(format: ArchiveFormat, entries: [ArchiveEntry], note: String? = nil) {
        let root = ArchiveNode(id: "/", name: "", isDirectory: true)
        var encrypted = false

        for entry in entries {
            var path = entry.path.replacingOccurrences(of: "\\", with: "/")
            while path.hasPrefix("./") { path.removeFirst(2) }
            while path.hasPrefix("/") { path.removeFirst() }
            if ArchiveListing.hiddenPrefixes.contains(where: path.hasPrefix) { continue }

            let components = path.split(separator: "/").map(String.init).filter { $0 != "." }
            guard let last = components.last, !ArchiveListing.hiddenNames.contains(last) else { continue }
            encrypted = encrypted || entry.isEncrypted

            var parent = root
            var current = ""
            for component in components.dropLast() {
                current += component + "/"
                parent = parent.child(named: component, path: current)
            }
            let id = current + last + (entry.isDirectory ? "/" : "")
            if entry.isDirectory {
                _ = parent.child(named: last, path: id)
            } else {
                parent.add(ArchiveNode(id: id, name: last, isDirectory: false, size: entry.size,
                                       modified: entry.modified, isEncrypted: entry.isEncrypted))
            }
        }

        let counts = root.finish()
        self.format = format
        self.root = root
        self.fileCount = counts.files
        self.folderCount = counts.folders
        self.expandedSize = root.size
        self.isEncrypted = encrypted
        self.note = note
    }
}

public enum ArchiveError: LocalizedError {
    case notAnArchive
    case corrupt(String)

    public var errorDescription: String? {
        switch self {
        case .notAnArchive: return "This file isn't a supported archive."
        case .corrupt(let detail): return "The archive appears to be damaged (\(detail))."
        }
    }
}

public enum ArchiveReader {
    /// Stop listing after this many entries; beyond it the tree is unusable anyway.
    public static let maxEntries = 50_000

    public static func read(url: URL, format: ArchiveFormat) throws -> ArchiveListing {
        switch format {
        case .zip: return try ZipReader.read(url: url)
        case .tar: return try TarReader.read(url: url, gzip: false)
        case .tarGzip: return try TarReader.read(url: url, gzip: true)
        }
    }
}
