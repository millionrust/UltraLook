import AppKit
import SwiftUI

/// Read-only, selectable, searchable source view with a line-number gutter.
/// Uses NSTextView (TextKit 1) so multi-megabyte files scroll smoothly.
struct CodeTextView: NSViewRepresentable {
    let source: NSAttributedString
    let wrap: Bool
    var showsLineNumbers = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.clipsToBounds = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(Theme.background)

        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView

        if showsLineNumbers {
            let ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
        }

        storage.setAttributedString(source)
        (scrollView.verticalRulerView as? LineNumberRulerView)?.textDidChange()
        context.coordinator.source = source
        apply(wrap: wrap, to: scrollView, textView: textView)
        context.coordinator.wrap = wrap
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if context.coordinator.source !== source {
            textView.textStorage?.setAttributedString(source)
            (scrollView.verticalRulerView as? LineNumberRulerView)?.textDidChange()
            context.coordinator.source = source
            textView.scroll(.zero)
        }
        if context.coordinator.wrap != wrap {
            apply(wrap: wrap, to: scrollView, textView: textView)
            context.coordinator.wrap = wrap
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var source: NSAttributedString?
        var wrap: Bool?
    }

    private func apply(wrap: Bool, to scrollView: NSScrollView, textView: NSTextView) {
        guard let container = textView.textContainer else { return }
        let contentWidth = scrollView.contentSize.width
        if wrap {
            scrollView.hasHorizontalScroller = false
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            container.widthTracksTextView = true
            textView.setFrameSize(NSSize(width: contentWidth, height: textView.frame.height))
            container.containerSize = NSSize(
                width: max(0, contentWidth - textView.textContainerInset.width * 2),
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            scrollView.hasHorizontalScroller = true
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.width, .height]
        }
        textView.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textView.string.utf16.count), actualCharacterRange: nil)
        textView.sizeToFit()
        scrollView.verticalRulerView?.needsDisplay = true
    }
}

/// Draws a line number beside the first fragment of every logical line.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(setNeedsRedraw),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(setNeedsRedraw),
            name: NSView.frameDidChangeNotification, object: textView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
        textView.postsFrameChangedNotifications = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var isFlipped: Bool { true }

    @objc private func setNeedsRedraw() {
        needsDisplay = true
    }

    func textDidChange() {
        let text = (textView?.string ?? "") as NSString
        var starts = [0]
        let length = text.length
        var index = 0
        while index < length {
            let range = text.range(of: "\n", options: .literal, range: NSRange(location: index, length: length - index))
            guard range.location != NSNotFound else { break }
            index = range.location + 1
            if index < length { starts.append(index) }
        }
        lineStarts = starts

        let digits = max(2, String(starts.count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        ruleThickness = ceil(CGFloat(digits) * digitWidth + 24)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        CodeTheme.gutterBackground.setFill()
        bounds.fill()
        CodeTheme.gutterBorder.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let length = textView.string.utf16.count
        let origin = textView.textContainerOrigin
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CodeTheme.lineNumber]
        let labelHeight = font.ascender - font.descender

        func draw(_ number: Int, fragment: NSRect) {
            let label = String(number) as NSString
            let size = label.size(withAttributes: attributes)
            let top = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: textView).y
            // Center within the text line, ignoring the extra line spacing below it.
            let textHeight = fragment.height - Theme.codeLineSpacing
            let y = top + (textHeight - labelHeight) / 2 + 0.5
            label.draw(at: NSPoint(x: ruleThickness - size.width - 12, y: y), withAttributes: attributes)
        }

        if length == 0 {
            draw(1, fragment: layoutManager.extraLineFragmentRect)
            return
        }

        var visible = textView.visibleRect
        visible.origin.x -= origin.x
        visible.origin.y -= origin.y
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)

        var line = firstLine(atOrBefore: chars.location)
        let end = NSMaxRange(chars)
        while line < lineStarts.count, lineStarts[line] <= end {
            let start = lineStarts[line]
            if start >= length { break }
            let glyph = layoutManager.glyphIndexForCharacter(at: start)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            draw(line + 1, fragment: fragment)
            line += 1
        }
    }

    private func firstLine(atOrBefore location: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
