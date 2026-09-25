import XCTest
@testable import UltraLookKit

final class HighlighterTests: XCTestCase {
    func testEveryLanguageCompilesWithOneGroupPerRule() {
        for language in Language.all where !language.isPlainText {
            let pattern = language.rules.map { "(\($0.pattern))" }.joined(separator: "|")
            let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            XCTAssertNotNil(regex, "\(language.id) doesn't compile")
            XCTAssertEqual(regex?.numberOfCaptureGroups, language.rules.count, "\(language.id) has a capturing group")
        }
    }

    func testKeywordsInsideStringsAndCommentsAreNotKeywords() {
        let code = #"let s = "if let" // return"#
        let tokens = SyntaxHighlighter.tokens(in: code, language: Language.detect(fileName: "a.swift"))
        let ns = code as NSString
        let kinds = tokens.map { (ns.substring(with: $0.range), $0.kind) }
        XCTAssertTrue(kinds.contains { $0 == ("let", .keyword) })
        XCTAssertTrue(kinds.contains { $0 == (#""if let""#, .string) })
        XCTAssertTrue(kinds.contains { $0 == ("// return", .comment) })
        XCTAssertFalse(kinds.contains { $0 == ("return", .keyword) })
    }

    func testDetectsLanguagesByNameAndExtension() {
        XCTAssertEqual(Language.detect(fileName: "main.rs").id, "rust")
        XCTAssertEqual(Language.detect(fileName: "Header.tsx").id, "typescript")
        XCTAssertEqual(Language.detect(fileName: "Makefile").id, "makefile")
        XCTAssertEqual(Language.detect(fileName: "Dockerfile.dev").id, "dockerfile")
        XCTAssertEqual(Language.detect(fileName: ".zshrc").id, "shell")
        XCTAssertEqual(Language.detect(fileName: "notes.unknown").id, "text")
    }

    func testFenceInfoMapsToLanguage() {
        XCTAssertEqual(Language.forFence("bash").id, "shell")
        XCTAssertEqual(Language.forFence("swift {linenos}").id, "swift")
        XCTAssertEqual(Language.forFence(nil).id, "text")
    }

    func testHighlightingSampleIsFast() {
        let line = #"func greet(_ name: String) -> String { return "Hello, \(name)!" } // 42"# + "\n"
        let text = String(repeating: line, count: 6_000)
        measure {
            _ = SyntaxHighlighter.tokens(in: text, language: .swift)
        }
    }
}

final class MarkdownTests: XCTestCase {
    func testSampleReadme() throws {
        let url = samplesURL.appendingPathComponent("README.md")
        let blocks = MarkdownParser.parse(try String(contentsOf: url, encoding: .utf8))

        XCTAssertEqual(blocks.first, .heading(level: 1, text: "Studio North"))
        XCTAssertTrue(blocks.contains(.code(info: "bash", text: "npm install\nnpm run dev")))
        XCTAssertTrue(blocks.contains(.quote([.paragraph("Build something small. Make it feel considered.")])))
        XCTAssertTrue(blocks.contains(.rule))

        let lists = blocks.compactMap { block -> MarkdownList? in
            if case .list(let list) = block { return list }
            return nil
        }
        XCTAssertEqual(lists.count, 2)
        XCTAssertEqual(lists[0].items.count, 3)
        XCTAssertEqual(lists[1].items.map(\.checked), [true, true, false])

        let table = blocks.compactMap { block -> MarkdownTable? in
            if case .table(let table) = block { return table }
            return nil
        }.first
        XCTAssertEqual(table?.header, ["Command", "What it does"])
        XCTAssertEqual(table?.rows.count, 3)
    }

    func testNestedAndOrderedLists() {
        let blocks = MarkdownParser.parse("""
        1. One
        2. Two
           - Nested a
           - Nested b
        3. Three
        """)
        guard case .list(let list) = blocks.first else { return XCTFail("expected a list") }
        XCTAssertTrue(list.ordered)
        XCTAssertEqual(list.items.count, 3)
        XCTAssertEqual(list.items[1].blocks.count, 2)
        guard case .list(let nested) = list.items[1].blocks[1] else { return XCTFail("expected nested list") }
        XCTAssertEqual(nested.items.count, 2)
    }

    func testParagraphsHeadingsAndBreaks() {
        let blocks = MarkdownParser.parse("""
        Title
        =====
        first line
        same paragraph

        ***
        ## Closed ##
        """)
        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Title"),
            .paragraph("first line same paragraph"),
            .rule,
            .heading(level: 2, text: "Closed"),
        ])
    }

    func testHTMLHeaderKeepsImagesAndText() {
        let blocks = MarkdownParser.parse("""
        <p align="center">
          <img src="logo.png" alt="Logo" width="80">
          <h1>My App</h1>
        </p>
        """)
        XCTAssertEqual(blocks, [.image(alt: "Logo", source: "logo.png"), .paragraph("My App")])
    }

    func testFrontMatterIsSkipped() {
        let blocks = MarkdownParser.parse("---\ntitle: Hi\n---\n# Body")
        XCTAssertEqual(blocks, [.heading(level: 1, text: "Body")])
    }
}

final class ArchiveTests: XCTestCase {
    func testSampleZip() throws {
        let listing = try ArchiveReader.read(url: samplesURL.appendingPathComponent("project.zip"), format: .zip)
        XCTAssertEqual(listing.fileCount, 7)
        XCTAssertEqual(listing.folderCount, 4)
        XCTAssertEqual(listing.expandedSize, 412)
        XCTAssertEqual(listing.root.children.map(\.name), ["public", "src", "tests", "package.json", "README.md"])
        let src = listing.root.children[1]
        XCTAssertEqual(src.children.map(\.name), ["components", "app.tsx"])
        XCTAssertEqual(src.size, 69 + 59 + 49)
        // macOS types ".ts" as MPEG-2 video; the listing should say TypeScript.
        XCTAssertEqual(listing.root.children[2].children.first?.kind, "TypeScript source")
    }

    func testTarAndTarGz() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let content = dir.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: content.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try Data(repeating: 65, count: 1000).write(to: content.appendingPathComponent("a/b/big.txt"))
        try Data("hi".utf8).write(to: content.appendingPathComponent("top.md"))
        let longName = String(repeating: "x", count: 120) + ".txt"
        try Data("long".utf8).write(to: content.appendingPathComponent(longName))
        defer { try? FileManager.default.removeItem(at: dir) }

        for (flags, gzip, name) in [("-cf", false, "t.tar"), ("-czf", true, "t.tgz")] {
            let archive = dir.appendingPathComponent(name)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.currentDirectoryURL = content
            process.arguments = [flags, archive.path, "a", "top.md", longName]
            process.environment = ["COPYFILE_DISABLE": "1"]
            try process.run()
            process.waitUntilExit()

            let format: ArchiveFormat = gzip ? .tarGzip : .tar
            XCTAssertEqual(ArchiveFormat.sniff(url: archive), format)
            let listing = try ArchiveReader.read(url: archive, format: format)
            XCTAssertEqual(listing.fileCount, 3, name)
            XCTAssertEqual(listing.folderCount, 2, name)
            XCTAssertEqual(listing.expandedSize, 1000 + 2 + 4, name)
            XCTAssertTrue(listing.root.children.contains { $0.name == longName }, name)
        }
    }

    func testTruncatedZipListsEntriesFromLocalHeaders() throws {
        let full = try Data(contentsOf: samplesURL.appendingPathComponent("project.zip"))
        let reader = ByteReader(data: full)
        // Cut the archive inside the data of package.json, before the central directory.
        var cut = 0
        while cut + 4 <= full.count {
            if reader.u32(at: cut) == 0x0403_4B50,
               ZipReader.entryName(full, at: cut + 30, length: Int(reader.u16(at: cut + 26)), flags: 0) == "package.json" { break }
            cut += 1
        }
        let listing = try ZipReader.read(data: full.prefix(cut + 60))
        XCTAssertEqual(listing.fileCount, 6) // README.md is missing
        XCTAssertEqual(listing.folderCount, 4)
        XCTAssertEqual(listing.note, "This archive is incomplete, so only part of it could be listed.")
    }

    func testGarbageIsRejected() {
        XCTAssertThrowsError(try ZipReader.read(data: Data("not a zip at all, nope".utf8)))
    }
}

final class TextFileTests: XCTestCase {
    func testDecoding() {
        XCTAssertEqual(TextFile.decode(Data("héllo\n".utf8))?.encodingName, "UTF-8")
        XCTAssertEqual(TextFile.decode(Data("hello".utf8))?.encodingName, "ASCII")
        XCTAssertNil(TextFile.decode(Data([0x00, 0x01, 0x02, 0x41])))
        // A truncated read that splits "é" still decodes as UTF-8.
        let split = Data("abcé".utf8).dropLast()
        XCTAssertEqual(TextFile.decode(split, isTruncated: true)?.text, "abc")
    }

    func testLineCount() {
        XCTAssertEqual(TextFile.countLines(""), 0)
        XCTAssertEqual(TextFile.countLines("a"), 1)
        XCTAssertEqual(TextFile.countLines("a\n"), 1)
        XCTAssertEqual(TextFile.countLines("a\nb"), 2)
        XCTAssertEqual(TextFile.countLines("a\n\n"), 2)
    }

    func testBinaryPlistBecomesXML() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Name": "Ultra Look"], format: .binary, options: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try XCTUnwrap(TextFile.load(url: url))
        XCTAssertTrue(file.text.contains("<string>Ultra Look</string>"))
    }

    func testDocumentSubtitle() throws {
        let preview = try LoadedPreview.prepare(url: samplesURL.appendingPathComponent("WorkspaceView.swift"))
        XCTAssertEqual(preview.document.badge, "CODE")
        XCTAssertTrue(preview.document.subtitle.hasSuffix("Swift · 22 lines"), preview.document.subtitle)
    }
}

private let samplesURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("App/Samples")
