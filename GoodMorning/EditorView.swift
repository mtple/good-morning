import AppKit
import SwiftUI

/// A plain-text page. No preview, no spellcheck squiggles, no smart punctuation.
/// Morning pages aren't for editing yourself.
struct EditorView: NSViewRepresentable {
    var text: String
    var isFocused = true  // false while the command palette is up
    var onChange: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PageTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        guard let textView = scrollView.documentView as? PageTextView else { return scrollView }
        textView.placeholder = "Just start typing. Whatever's on your mind counts."
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 32, height: 64)
        textView.font = Typography.font
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
        textView.defaultParagraphStyle = Typography.paragraph
        textView.typingAttributes = Typography.attributes

        load(text, into: textView)
        Task { @MainActor in
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only replace the text when it changed from outside (a new day, a new folder),
        // never while typing, or the caret would jump.
        if textView.string != text {
            load(text, into: textView)
        }
        // Take the caret back when the command palette closes.
        if isFocused, !context.coordinator.wasFocused {
            textView.window?.makeFirstResponder(textView)
        }
        context.coordinator.wasFocused = isFocused
    }

    /// Put the text in and the caret at the end, ready to keep going.
    private func load(_ text: String, into textView: NSTextView) {
        textView.string = text
        let length = (text as NSString).length
        textView.textStorage?.setAttributes(Typography.attributes, range: NSRange(location: 0, length: length))
        textView.undoManager?.removeAllActions()
        textView.setSelectedRange(NSRange(location: length, length: 0))
        textView.scrollRangeToVisible(NSRange(location: length, length: 0))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: @MainActor (String) -> Void
        var wasFocused = true

        init(onChange: @escaping @MainActor (String) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }
    }
}

/// The page itself. An empty page shows a hint, set in the page's own type, where the first words will go.
final class PageTextView: NSTextView {
    var placeholder = ""
    private var showsPlaceholder = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        showsPlaceholder = string.isEmpty && !placeholder.isEmpty
        guard showsPlaceholder else { return }
        var attributes = Typography.attributes
        attributes[.foregroundColor] = NSColor.tertiaryLabelColor
        let x = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0)
        let rect = NSRect(x: x, y: textContainerOrigin.y, width: bounds.width - 2 * x, height: bounds.height)
        NSAttributedString(string: placeholder, attributes: attributes).draw(in: rect)
    }

    override func didChangeText() {
        super.didChangeText()
        // Typing only redraws around the new letters, so clear (or bring back) the whole hint.
        if showsPlaceholder != string.isEmpty { needsDisplay = true }
    }
}

enum Typography {
    static var font: NSFont {
        let base = NSFont.systemFont(ofSize: 18)
        if let serif = base.fontDescriptor.withDesign(.serif) {
            return NSFont(descriptor: serif, size: 18) ?? base
        }
        return base
    }

    static var paragraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.45
        style.paragraphSpacing = 10
        return style
    }

    static var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }
}
