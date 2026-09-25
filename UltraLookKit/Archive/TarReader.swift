import Compression
import Foundation

/// Lists tar and tar.gz archives. Tarballs have no index, so the reader walks
/// the headers in order, skipping file contents (and inflating gzip in a stream).
enum TarReader {
    /// Stop inflating a tarball after this many bytes so huge archives stay quick.
    static let maxInflatedBytes: Int64 = 1 << 30

    static func read(url: URL, gzip: Bool) throws -> ArchiveListing {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        return try read(data: data, gzip: gzip)
    }

    static func read(data: Data, gzip: Bool) throws -> ArchiveListing {
        var parser = TarParser()
        if gzip {
            var inflated: Int64 = 0
            try Gzip.inflate(data) { chunk in
                parser.feed(chunk)
                inflated += Int64(chunk.count)
                if inflated >= maxInflatedBytes, !parser.isFinished {
                    parser.note = "Showing entries from the first \(Format.bytes(maxInflatedBytes)) of the archive."
                    return false
                }
                return !parser.isFinished
            }
        } else {
            data.withUnsafeBytes { raw in
                parser.feed(UnsafeBufferPointer(start: raw.bindMemory(to: UInt8.self).baseAddress, count: raw.count))
            }
        }
        if parser.entries.isEmpty, !parser.sawHeader {
            throw ArchiveError.corrupt("no tar headers")
        }
        return ArchiveListing(format: gzip ? .tarGzip : .tar, entries: parser.entries, note: parser.note)
    }
}

struct TarParser {
    private(set) var entries: [ArchiveEntry] = []
    private(set) var isFinished = false
    private(set) var sawHeader = false
    var note: String?

    private var block: [UInt8] = []
    private var skip: Int64 = 0
    private var metadata: (type: UInt8, remaining: Int, padding: Int)?
    private var metadataBytes: [UInt8] = []
    private var longName: String?
    private var paxPath: String?
    private var paxSize: Int64?

    mutating func feed(_ bytes: UnsafeBufferPointer<UInt8>) {
        var i = 0
        let count = bytes.count
        while i < count, !isFinished {
            if skip > 0 {
                let n = Int(min(skip, Int64(count - i)))
                i += n
                skip -= Int64(n)
                continue
            }
            if let meta = metadata {
                let n = min(meta.remaining, count - i)
                metadataBytes.append(contentsOf: bytes[i ..< i + n])
                i += n
                metadata?.remaining -= n
                if metadata?.remaining == 0 {
                    finishMetadata(type: meta.type)
                    metadata = nil
                    skip = Int64(meta.padding)
                }
                continue
            }
            let n = min(512 - block.count, count - i)
            block.append(contentsOf: bytes[i ..< i + n])
            i += n
            if block.count == 512 {
                processHeader(block)
                block.removeAll(keepingCapacity: true)
            }
        }
    }

    private mutating func processHeader(_ h: [UInt8]) {
        if h.allSatisfy({ $0 == 0 }) {
            isFinished = true
            return
        }
        guard checksumMatches(h) else {
            note = note ?? "The archive ends with unreadable data."
            isFinished = true
            return
        }
        sawHeader = true

        var name = cString(h[0..<100])
        if String(bytes: h[257..<262], encoding: .ascii) == "ustar" {
            let prefix = cString(h[345..<500])
            if !prefix.isEmpty { name = prefix + "/" + name }
        }
        let size = number(h[124..<136])
        let mtime = number(h[136..<148])
        let type = h[156]
        let padded = Int((size + 511) / 512 * 512)

        switch type {
        case UInt8(ascii: "L"), UInt8(ascii: "x"):
            metadataBytes.removeAll()
            metadata = (type, Int(size), padded - Int(size))
            if size == 0 { metadata = nil }
            return
        case UInt8(ascii: "g"), UInt8(ascii: "K"):
            skip = Int64(padded)
            return
        default:
            break
        }

        if entries.count >= ArchiveReader.maxEntries {
            note = "Showing the first \(ArchiveReader.maxEntries) entries."
            isFinished = true
            return
        }

        let path = paxPath ?? longName ?? name
        let entrySize = paxSize ?? size
        let isDirectory = type == UInt8(ascii: "5") || path.hasSuffix("/")
        entries.append(ArchiveEntry(
            path: path,
            isDirectory: isDirectory,
            size: isDirectory ? 0 : entrySize,
            compressedSize: nil,
            modified: mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil,
            isSymlink: type == UInt8(ascii: "2")
        ))
        longName = nil
        paxPath = nil
        paxSize = nil
        // Links carry no data even if a size is recorded.
        let hasData = !(type == UInt8(ascii: "1") || type == UInt8(ascii: "2") || isDirectory)
        skip = hasData ? Int64((entrySize + 511) / 512 * 512) : 0
    }

    private mutating func finishMetadata(type: UInt8) {
        if type == UInt8(ascii: "L") {
            longName = cString(metadataBytes[...])
            return
        }
        // PAX records: "<length> <key>=<value>\n"
        guard let text = String(bytes: metadataBytes, encoding: .utf8) else { return }
        for record in text.split(separator: "\n") {
            guard let space = record.firstIndex(of: " ") else { continue }
            let pair = record[record.index(after: space)...]
            guard let equals = pair.firstIndex(of: "=") else { continue }
            let key = pair[..<equals]
            let value = String(pair[pair.index(after: equals)...])
            if key == "path" { paxPath = value }
            if key == "size" { paxSize = Int64(value) }
        }
    }

    private func checksumMatches(_ h: [UInt8]) -> Bool {
        let stored = number(h[148..<156])
        // Some old writers summed signed bytes; accept either.
        var unsigned: Int64 = 0
        var signed: Int64 = 0
        for (index, byte) in h.enumerated() {
            let inChecksum = (148..<156).contains(index)
            unsigned += inChecksum ? 32 : Int64(byte)
            signed += inChecksum ? 32 : Int64(Int8(bitPattern: byte))
        }
        return stored == unsigned || stored == signed
    }

    private func cString(_ bytes: ArraySlice<UInt8>) -> String {
        let trimmed = bytes.prefix { $0 != 0 }
        return String(bytes: trimmed, encoding: .utf8) ?? String(bytes: trimmed, encoding: .isoLatin1) ?? ""
    }

    /// Octal ASCII, or GNU base-256 when the high bit of the first byte is set.
    private func number(_ bytes: ArraySlice<UInt8>) -> Int64 {
        guard let first = bytes.first else { return 0 }
        if first & 0x80 != 0 {
            var value: Int64 = Int64(first & 0x7F)
            for byte in bytes.dropFirst() { value = value << 8 | Int64(byte) }
            return value
        }
        var value: Int64 = 0
        var started = false
        for byte in bytes {
            if byte >= 0x30, byte <= 0x37 {
                value = value * 8 + Int64(byte - 0x30)
                started = true
            } else if !started, byte == 0x20 || byte == 0 {
                continue
            } else {
                break
            }
        }
        return value
    }
}

enum Gzip {
    enum Failure: Error { case badHeader, inflateFailed }

    /// Inflates a gzip member in chunks. Return false from `body` to stop early.
    static func inflate(_ data: Data, body: (UnsafeBufferPointer<UInt8>) -> Bool) throws {
        let header = try headerLength(data)
        let bufferSize = 256 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.inflateFailed
        }
        defer { compression_stream_destroy(stream) }

        try data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.pointee.src_ptr = base + header
            stream.pointee.src_size = raw.count - header
            while true {
                stream.pointee.dst_ptr = destination
                stream.pointee.dst_size = bufferSize
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.pointee.dst_size
                if produced > 0, !body(UnsafeBufferPointer(start: destination, count: produced)) { return }
                switch status {
                case COMPRESSION_STATUS_OK: continue
                case COMPRESSION_STATUS_END: return
                default: throw Failure.inflateFailed
                }
            }
        }
    }

    static func headerLength(_ data: Data) throws -> Int {
        let r = ByteReader(data: data)
        guard data.count > 18, r.u8(at: 0) == 0x1F, r.u8(at: 1) == 0x8B, r.u8(at: 2) == 8 else {
            throw Failure.badHeader
        }
        let flags = r.u8(at: 3)
        var offset = 10
        if flags & 0x04 != 0 { offset += 2 + Int(r.u16(at: offset)) }
        if flags & 0x08 != 0 { while offset < data.count, r.u8(at: offset) != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while offset < data.count, r.u8(at: offset) != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < data.count else { throw Failure.badHeader }
        return offset
    }
}
