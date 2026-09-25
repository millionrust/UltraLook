import SwiftUI

struct CodePreview: View {
    let file: TextFile
    let source: NSAttributedString

    @AppStorage("wrapLines") private var wrap = false

    var body: some View {
        VStack(spacing: 0) {
            SectionBar(icon: "chevron.left.forwardslash.chevron.right", title: "Source") {
                PillButton(title: "Wrap", isOn: wrap) { wrap.toggle() }
            }
            CodeTextView(source: source, wrap: wrap)
            if file.isTruncated {
                FooterBar(text: "Showing the first \(Format.bytes(Int64(TextFile.maxBytes))) of this file.")
            }
        }
    }
}
