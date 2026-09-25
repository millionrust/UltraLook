import SwiftUI
import UltraLookKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 330)
            previewPane
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.canvas)
        .ignoresSafeArea()
        .onAppear {
            if case .empty = model.state, let first = model.samples.first(where: { $0.pathExtension == "md" }) {
                model.load(first)
            }
        }
    }

    private var previewPane: some View {
        VStack(spacing: 14) {
            SampleTabs()
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.card)
                    .shadow(color: .black.opacity(0.10), radius: 24, y: 10)
                previewContent
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(Palette.accent.opacity(0.06).clipShape(RoundedRectangle(cornerRadius: 12)))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.cardBorder))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.load(url)
                return true
            } isTargeted: { isDropTargeted = $0 }

            HStack {
                Text("Drop any file here to preview it, or press ⌘O.")
                Spacer()
                Label("Your files stay on your Mac.", systemImage: "lock")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch model.state {
        case .empty:
            MessageView(icon: "arrow.down.doc", title: "Drop a file", detail: "Markdown, source code, and archives.")
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let preview):
            PreviewView(preview: preview)
                .id(preview.document.url)
        case .failed(let url, let message):
            MessageView(icon: "exclamationmark.triangle", title: "Can't preview \(url.lastPathComponent)", detail: message)
        }
    }
}

private struct SampleTabs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.samples, id: \.self) { url in
                let selected = currentURL == url
                Button {
                    model.load(url)
                } label: {
                    Label(url.lastPathComponent, systemImage: icon(for: url))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(Capsule().fill(selected ? Palette.accent : Palette.card))
                        .overlay(Capsule().strokeBorder(selected ? Color.clear : Palette.cardBorder))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("Open…") { model.showOpenPanel() }
                .controlSize(.regular)
        }
    }

    private var currentURL: URL? {
        switch model.state {
        case .loaded(let preview): return preview.document.url
        case .loading(let url), .failed(let url, _): return url
        case .empty: return nil
        }
    }

    private func icon(for url: URL) -> String {
        switch url.pathExtension {
        case "md": return "doc.richtext"
        case "zip": return "doc.zipper"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                Text("Ultra Look")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.top, 44)

            Text("A LITTLE MORE SPACE.")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(.secondary)
                .padding(.top, 36)

            Text("Look inside.\nJust press Space.")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.8)
                .lineSpacing(-2)
                .padding(.top, 10)

            Text("Readable Markdown, highlighted source code with line numbers, and archives you can browse without extracting — right in Finder's Quick Look.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 18) {
                Step(number: 1, title: "Turn on the extension", detail: "In System Settings › General › Login Items & Extensions › Quick Look, enable Ultra Look.") {
                    Button("Open Extension Settings") { model.openExtensionSettings() }
                }
                Step(number: 2, title: "Select a file in Finder", detail: "Try the samples, or any README, source file, or zip.") {
                    Button("Show Sample Files") { model.revealSamples() }
                }
                Step(number: 3, title: "Press Space", detail: "Ultra Look takes over the preview for the file types it supports.") {
                    KeyCap(label: "Space")
                }
            }
            .padding(.top, 30)

            Spacer()

            HStack(spacing: 6) {
                Chip(text: "Markdown")
                Chip(text: "70+ languages")
                Chip(text: "Zip · Tar")
            }
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar)
        .overlay(alignment: .trailing) { Palette.cardBorder.frame(width: 1) }
    }
}

private struct Step<Accessory: View>: View {
    let number: Int
    let title: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
    }
}

private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.cardBorder))
            .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
    }
}

private struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .overlay(Capsule().strokeBorder(Palette.cardBorder))
    }
}

enum Palette {
    static let accent = Color("AccentColor")
    static let canvas = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.955, alpha: 1) })
    static let sidebar = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.985, alpha: 1) })
    static let card = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(white: 0.16, alpha: 1) : .white })
    static let cardBorder = Color(nsColor: NSColor(name: nil) { $0.isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.08) })
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
