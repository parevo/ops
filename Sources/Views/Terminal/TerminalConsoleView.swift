import AppKit
import SwiftUI

/// High-performance monospaced console backed by NSTextView (not thousands of SwiftUI Text views).
struct TerminalConsoleView: NSViewRepresentable {
    @Binding var text: String
    var isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        applyColors(to: textView)

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lastLength = 0
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        applyColors(to: textView)

        // Append-only fast path
        if text.count >= context.coordinator.lastLength,
           textView.string.count == context.coordinator.lastLength {
            let start = text.index(text.startIndex, offsetBy: context.coordinator.lastLength)
            let chunk = String(text[start...])
            if !chunk.isEmpty {
                textView.textStorage?.append(NSAttributedString(string: chunk, attributes: textAttributes(for: textView)))
                context.coordinator.lastLength = text.count
                textView.scrollToEndOfDocument(nil)
            }
            return
        }

        textView.string = text
        context.coordinator.lastLength = text.count
        textView.scrollToEndOfDocument(nil)
    }

    private func applyColors(to textView: NSTextView) {
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.insertionPointColor = NSColor.textColor
    }

    private func textAttributes(for textView: NSTextView) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: textView.textColor ?? NSColor.textColor
        ]
    }

    final class Coordinator {
        var textView: NSTextView?
        var lastLength = 0
    }
}
