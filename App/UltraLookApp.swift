import AppKit
import SwiftUI
import UltraLookKit

@main
struct UltraLookApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Ultra Look", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.showOpenPanel() }
                    .keyboardShortcut("o")
            }
        }
    }
}

/// Files opened from Finder ("Open With", Dock drops, `open -a "Ultra Look" file`) land in the preview pane.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in AppModel.shared.load(url) }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum State {
        case empty
        case loading(URL)
        case loaded(LoadedPreview)
        case failed(URL, String)
    }

    @Published private(set) var state: State = .empty
    private var loadID = UUID()

    var samplesURL: URL? { Bundle.main.url(forResource: "Samples", withExtension: nil) }

    var samples: [URL] {
        guard let folder = samplesURL else { return [] }
        let names = ["README.md", "WorkspaceView.swift", "project.zip"]
        return names.map { folder.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func load(_ url: URL) {
        let id = UUID()
        loadID = id
        state = .loading(url)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try LoadedPreview.prepare(url: url) }
            }.value
            guard loadID == id else { return }
            switch result {
            case .success(let preview): state = .loaded(preview)
            case .failure(let error): state = .failed(url, error.localizedDescription)
            }
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Preview"
        if panel.runModal() == .OK, let url = panel.url {
            load(url)
        }
    }

    func revealSamples() {
        guard !samples.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(samples)
    }

    func openExtensionSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
