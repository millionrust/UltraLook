import SwiftUI

struct ArchivePreview: View {
    let listing: ArchiveListing

    @State private var expanded: Set<String>
    @State private var selection: String?

    private static let sizeWidth: CGFloat = 90
    private static let kindWidth: CGFloat = 150

    init(listing: ArchiveListing) {
        self.listing = listing
        // Small archives open fully expanded; big ones start collapsed.
        var initial = Set<String>()
        if listing.fileCount + listing.folderCount <= 400 {
            func collect(_ node: ArchiveNode) {
                for child in node.children where child.isDirectory {
                    initial.insert(child.id)
                    collect(child)
                }
            }
            collect(listing.root)
        }
        _expanded = State(initialValue: initial)
    }

    private struct Row: Identifiable {
        let node: ArchiveNode
        let depth: Int
        var id: String { node.id }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        func walk(_ node: ArchiveNode, depth: Int) {
            for child in node.children {
                rows.append(Row(node: child, depth: depth))
                if child.isDirectory, expanded.contains(child.id) {
                    walk(child, depth: depth + 1)
                }
            }
        }
        walk(listing.root, depth: 0)
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionBar(icon: "folder", title: "Contents") {
                if listing.isEncrypted {
                    Label("Encrypted", systemImage: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            columnHeader
            if listing.root.children.isEmpty {
                MessageView(icon: "archivebox", title: "Empty archive", detail: "This archive doesn't contain any files.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            rowView(row)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            FooterBar(text: footer)
        }
    }

    private var footer: String {
        var parts = [Format.count(listing.fileCount, "file"), Format.count(listing.folderCount, "folder")]
        if let note = listing.note { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Name")
            Spacer(minLength: 8)
            Text("Size").frame(width: Self.sizeWidth, alignment: .trailing)
            Text("Kind").frame(width: Self.kindWidth, alignment: .leading).padding(.leading, 20)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 26)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
    }

    private func rowView(_ row: Row) -> some View {
        let node = row.node
        let isExpanded = expanded.contains(node.id)
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Color.clear.frame(width: CGFloat(row.depth) * 16, height: 1)
                if node.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(node) }
                } else {
                    Color.clear.frame(width: 12, height: 1)
                }
                Image(systemName: icon(for: node))
                    .font(.system(size: 11.5))
                    .foregroundStyle(node.isDirectory ? Theme.folder : Color.secondary)
                    .frame(width: 16)
                Text(node.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if node.isEncrypted {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Text(Format.bytes(node.size))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: Self.sizeWidth, alignment: .trailing)
            Text(node.kind)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.kindWidth, alignment: .leading)
                .padding(.leading, 20)
        }
        .padding(.horizontal, 16)
        .frame(height: 24)
        .background(selection == node.id ? Theme.selectedRow : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if node.isDirectory { toggle(node) } }
        .simultaneousGesture(TapGesture().onEnded { selection = node.id })
    }

    private func toggle(_ node: ArchiveNode) {
        withAnimation(.easeOut(duration: 0.15)) {
            if expanded.contains(node.id) {
                expanded.remove(node.id)
            } else {
                expanded.insert(node.id)
            }
        }
    }

    private func icon(for node: ArchiveNode) -> String {
        if node.isDirectory { return "folder.fill" }
        switch (node.name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tiff", "bmp", "ico", "icns": return "photo"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": return "film"
        case "mp3", "wav", "m4a", "aac", "flac", "ogg": return "waveform"
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar": return "doc.zipper"
        case "pdf": return "doc.richtext"
        case "md", "markdown", "txt", "rtf": return "doc.text"
        default:
            return Language.detect(fileName: node.name).isPlainText ? "doc" : "chevron.left.forwardslash.chevron.right"
        }
    }
}
