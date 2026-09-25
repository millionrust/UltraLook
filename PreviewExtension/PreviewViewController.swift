import AppKit
import Quartz
import SwiftUI
import UltraLookKit

final class PreviewViewController: NSViewController, QLPreviewingController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 620))
        preferredContentSize = NSSize(width: 820, height: 620)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        do {
            let preview = try await Task.detached(priority: .userInitiated) {
                try LoadedPreview.prepare(url: url)
            }.value
            show(PreviewView(preview: preview))
        } catch {
            // Throwing leaves Quick Look with a blank or generic panel; say what went wrong instead.
            show(MessageView(icon: "exclamationmark.triangle", title: "Can't preview \(url.lastPathComponent)", detail: error.localizedDescription))
        }
    }

    private func show<Content: View>(_ content: Content) {
        view.subviews.forEach { $0.removeFromSuperview() }
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
