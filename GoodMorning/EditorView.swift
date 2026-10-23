import AppKit
import SwiftUI

/// A plain-text page. No preview, no spellcheck squiggles, no smart punctuation.
/// Morning pages aren't for editing yourself.
struct EditorView: NSViewRepresentable {
    var text: String
    var onChange: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
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

        init(onChange: @escaping @MainActor (String) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }
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
