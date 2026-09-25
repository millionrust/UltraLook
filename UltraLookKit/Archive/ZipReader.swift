import Foundation

/// Lists a zip archive by reading only its central directory — nothing is extracted.
enum ZipReader {
    static func read(url: URL) throws -> ArchiveListing {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        return try read(data: data)
    }

    static func read(data: Data) throws -> ArchiveListing {
        let reader = ByteReader(data: data)
        guard let eocd = findEndOfCentralDirectory(data) else {
            // Interrupted downloads and streamed zips lack the index; list what the file headers say.
            return try scanLocalHeaders(data)
        }

        var entryCount = Int(reader.u16(at: eocd + 10))
        var directorySize = Int64(reader.u32(at: eocd + 12))
        var directoryOffset = Int64(reader.u32(at: eocd + 16))

        // ZIP64: the classic record holds 0xFFFF / 0xFFFFFFFF placeholders.
        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF || directorySize == 0xFFFF_FFFF,
           eocd >= 20, reader.u32(at: eocd - 20) == 0x0706_4B50 {
            let zip64Offset = Int(reader.u64(at: eocd - 20 + 8))
            if zip64Offset + 56 <= data.count, reader.u32(at: zip64Offset) == 0x0606_4B50 {
                entryCount = Int(reader.u64(at: zip64Offset + 32))
                directorySize = Int64(reader.u64(at: zip64Offset + 40))
                directoryOffset = Int64(reader.u64(at: zip64Offset + 48))
            }
        }

        // Self-extracting or prefixed archives shift every offset by the prefix length.
        let prefix = Int64(eocd) - directorySize - directoryOffset
        var offset = Int(directoryOffset + max(0, prefix))
        var entries: [ArchiveEntry] = []
        entries.reserveCapacity(min(entryCount, ArchiveReader.maxEntries))
        var note: String?

        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, reader.u32(at: offset) == 0x0201_4B50 else {
                note = "Some entries couldn't be read."
                break
            }
            if entries.count >= ArchiveReader.maxEntries {
                note = "Showing the first \(ArchiveReader.maxEntries) entries."
                break
            }
            let flags = reader.u16(at: offset + 8)
            let dosTime = reader.u16(at: offset + 12)
            let dosDate = reader.u16(at: offset + 14)
            var compressed = Int64(reader.u32(at: offset + 20))
            var uncompressed = Int64(reader.u32(at: offset + 24))
            let nameLength = Int(reader.u16(at: offset + 28))
            let extraLength = Int(reader.u16(at: offset + 30))
            let commentLength = Int(reader.u16(at: offset + 32))
            let madeBy = reader.u16(at: offset + 4) >> 8
            let externalAttributes = reader.u32(at: offset + 38)

            let nameStart = offset + 46
            guard nameStart + nameLength + extraLength <= data.count else {
                note = "Some entries couldn't be read."
                break
            }
            let name = entryName(data, at: nameStart, length: nameLength, flags: flags)

            // ZIP64 extended information extra field (0x0001).
            var extra = nameStart + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let id = reader.u16(at: extra)
                let size = Int(reader.u16(at: extra + 2))
                if id == 0x0001 {
                    var field = extra + 4
                    if uncompressed == 0xFFFF_FFFF, field + 8 <= extraEnd {
                        uncompressed = Int64(reader.u64(at: field)); field += 8
                    }
                    if compressed == 0xFFFF_FFFF, field + 8 <= extraEnd {
                        compressed = Int64(reader.u64(at: field))
                    }
                }
                extra += 4 + size
            }

            let unixMode = madeBy == 3 ? externalAttributes >> 16 : 0
            let isSymlink = unixMode & 0o170000 == 0o120000
            let isDirectory = name.hasSuffix("/") || (externalAttributes & 0x10 != 0 && uncompressed == 0)

            entries.append(ArchiveEntry(
                path: name,
                isDirectory: isDirectory,
                size: uncompressed,
                compressedSize: compressed,
                modified: dosDateTime(date: dosDate, time: dosTime),
                isEncrypted: flags & 0x1 != 0,
                isSymlink: isSymlink
            ))
            offset = nameStart + nameLength + extraLength + commentLength
        }

        return ArchiveListing(format: .zip, entries: entries, note: note)
    }

    /// Walks local file headers from the start of the file. Used when the central
    /// directory is missing, e.g. a download that stopped partway.
    static func scanLocalHeaders(_ data: Data) throws -> ArchiveListing {
        let reader = ByteReader(data: data)
        var entries: [ArchiveEntry] = []
        var offset = 0
        var isComplete = true
        var note: String?

        while offset + 30 <= data.count, reader.u32(at: offset) == 0x0403_4B50 {
            if entries.count >= ArchiveReader.maxEntries {
                note = "Showing the first \(ArchiveReader.maxEntries) entries."
                break
            }
            let flags = reader.u16(at: offset + 6)
            let dosTime = reader.u16(at: offset + 10)
            let dosDate = reader.u16(at: offset + 12)
            var compressed = Int64(reader.u32(at: offset + 18))
            var uncompressed = Int64(reader.u32(at: offset + 22))
            let nameLength = Int(reader.u16(at: offset + 26))
            let extraLength = Int(reader.u16(at: offset + 28))
            let nameStart = offset + 30
            guard nameStart + nameLength <= data.count else {
                isComplete = false
                break
            }
            let name = entryName(data, at: nameStart, length: nameLength, flags: flags)

            // ZIP64 local extra field carries both sizes.
            var extra = nameStart + nameLength
            let extraEnd = min(extra + extraLength, data.count)
            while extra + 4 <= extraEnd {
                let id = reader.u16(at: extra)
                let size = Int(reader.u16(at: extra + 2))
                if id == 0x0001, extra + 20 <= extraEnd {
                    uncompressed = Int64(reader.u64(at: extra + 4))
                    compressed = Int64(reader.u64(at: extra + 12))
                }
                extra += 4 + size
            }

            var next = nameStart + nameLength + extraLength
            let hasDescriptor = flags & 0x08 != 0
            if hasDescriptor, compressed == 0 {
                // Sizes follow the data in a descriptor; find it or the next header.
                let search = min(next, data.count)..<data.count
                if let range = data.range(of: Data([0x50, 0x4B, 0x07, 0x08]), in: search) {
                    let position = range.lowerBound - data.startIndex
                    compressed = Int64(reader.u32(at: position + 8))
                    uncompressed = Int64(reader.u32(at: position + 12))
                    next = position + 16
                } else if let range = data.range(of: Data([0x50, 0x4B, 0x03, 0x04]), in: search) {
                    next = range.lowerBound - data.startIndex
                } else {
                    next = data.count + 1
                }
            } else {
                next += Int(compressed)
                if hasDescriptor {
                    next += reader.u32(at: next) == 0x0807_4B50 ? 16 : 12
                }
            }

            entries.append(ArchiveEntry(
                path: name,
                isDirectory: name.hasSuffix("/"),
                size: uncompressed,
                compressedSize: compressed,
                modified: dosDateTime(date: dosDate, time: dosTime),
                isEncrypted: flags & 0x1 != 0
            ))
            if next > data.count {
                isComplete = false
                break
            }
            offset = next
        }

        guard !entries.isEmpty else { throw ArchiveError.corrupt("no central directory") }
        if note == nil {
            note = isComplete
                ? "The archive has no index; listed from its file headers."
                : "This archive is incomplete, so only part of it could be listed."
        }
        return ArchiveListing(format: .zip, entries: entries, note: note)
    }

    static func entryName(_ data: Data, at start: Int, length: Int, flags: UInt16) -> String {
        let bytes = data[data.startIndex + start ..< data.startIndex + start + length]
        let utf8 = flags & 0x0800 != 0
        return String(data: bytes, encoding: .utf8)
            ?? (utf8 ? nil : String(data: bytes, encoding: .isoLatin1))
            ?? "?"
    }

    /// The end record sits within the last 64 KiB + 22 bytes (max comment length).
    static func findEndOfCentralDirectory(_ data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let reader = ByteReader(data: data)
        let lowest = max(0, data.count - 22 - 0xFFFF)
        var position = data.count - 22
        while position >= lowest {
            if reader.u32(at: position) == 0x0605_4B50 { return position }
            position -= 1
        }
        return nil
    }

    static func dosDateTime(date: UInt16, time: UInt16) -> Date? {
        guard date != 0 else { return nil }
        var components = DateComponents()
        components.year = Int(date >> 9) + 1980
        components.month = Int((date >> 5) & 0xF)
        components.day = Int(date & 0x1F)
        components.hour = Int(time >> 11)
        components.minute = Int((time >> 5) & 0x3F)
        components.second = Int(time & 0x1F) * 2
        return Calendar(identifier: .gregorian).date(from: components)
    }
}

/// Little-endian reads that return 0 instead of trapping past the end.
struct ByteReader {
    let data: Data

    func u8(at offset: Int) -> UInt8 {
        guard offset >= 0, offset < data.count else { return 0 }
        return data[data.startIndex + offset]
    }

    func u16(at offset: Int) -> UInt16 {
        UInt16(u8(at: offset)) | UInt16(u8(at: offset + 1)) << 8
    }

    func u32(at offset: Int) -> UInt32 {
        UInt32(u16(at: offset)) | UInt32(u16(at: offset + 2)) << 16
    }

    func u64(at offset: Int) -> UInt64 {
        UInt64(u32(at: offset)) | UInt64(u32(at: offset + 4)) << 32
    }
}
