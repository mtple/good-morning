import AppKit
import SwiftUI

/// A plain-text page. No preview, no spellcheck squiggles, no smart punctuation.
/// Morning pages aren't for editing yourself.
struct EditorView: NSViewRepresentable {
    var text: String
    var fontSize = Prefs.defaultFontSize
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
        textView.updateMargins()
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.fontSize = fontSize
        textView.applyTypography()

        textView.load(text)
        Task { @MainActor in
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let textView = scrollView.documentView as? PageTextView else { return }
        // Only replace the text when it changed from outside (a new day, a new folder),
        // never while typing, or the caret would jump.
        if textView.string != text {
            textView.load(text)
        }
        textView.fontSize = fontSize
        // Take the caret back when the command palette closes.
        if isFocused, !context.coordinator.wasFocused {
            textView.window?.makeFirstResponder(textView)
        }
        context.coordinator.wasFocused = isFocused
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
///
/// The page scrolls on past its last line by half a screen, so the line you're writing needn't sit at the bottom.
/// As you type, the caret keeps its place on the screen (no lower than two thirds of the way down) and the page
/// moves up under it instead.
final class PageTextView: NSTextView {
    var placeholder = ""
    var fontSize = Prefs.defaultFontSize {
        didSet { if fontSize != oldValue { applyTypography() } }
    }
    private var showsPlaceholder = false
    private var caretOffset: CGFloat?  // how far down the visible page the caret was just before this edit

    private static let topMargin: CGFloat = 64
    private static let sideMargin: CGFloat = 32
    private static let lowestCaret: CGFloat = 2 / 3  // of the way down the visible page

    /// Put the text in and the caret at the end, ready to keep going, about halfway down the screen.
    func load(_ text: String) {
        string = text
        let length = (text as NSString).length
        textStorage?.setAttributes(Typography.attributes(size: fontSize), range: NSRange(location: 0, length: length))
        undoManager?.removeAllActions()
        setSelectedRange(NSRange(location: length, length: 0))
        // Once the page is laid out and sized. The end of the page is half a screen below the last line.
        Task { @MainActor in self.scrollToEndOfDocument(nil) }
    }

    /// The font, line spacing and typing style for the current size, over everything already on the page.
    func applyTypography() {
        let attributes = Typography.attributes(size: fontSize)
        font = attributes[.font] as? NSFont
        defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        typingAttributes = attributes
        if let storage = textStorage, !hasMarkedText() {
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
        needsDisplay = true
        scrollRangeToVisible(selectedRange())
    }

    /// AppKit leaves the same inset above and below the text. It's made big enough for the room wanted below
    /// (half the visible page), and textContainerOrigin moves the text back up to the top margin.
    func updateMargins() {
        let visibleHeight = enclosingScrollView?.contentSize.height ?? 800
        let inset = NSSize(width: Self.sideMargin, height: ((Self.topMargin + visibleHeight / 2) / 2).rounded())
        if textContainerInset != inset { textContainerInset = inset }
    }

    override var textContainerOrigin: NSPoint {
        NSPoint(x: super.textContainerOrigin.x, y: Self.topMargin)
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        updateMargins()  // the window changed size, or filled the screen
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        showsPlaceholder = string.isEmpty && !placeholder.isEmpty
        guard showsPlaceholder else { return }
        var attributes = Typography.attributes(size: fontSize)
        attributes[.foregroundColor] = NSColor.tertiaryLabelColor
        let x = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0)
        let rect = NSRect(x: x, y: textContainerOrigin.y, width: bounds.width - 2 * x, height: bounds.height)
        NSAttributedString(string: placeholder, attributes: attributes).draw(in: rect)
    }

    override func keyDown(with event: NSEvent) {
        if let stroke = Typewriter.stroke(for: event) { Typewriter.shared.play(stroke) }
        super.keyDown(with: event)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        // Only when the caret is on screen. Typing somewhere scrolled out of sight scrolls to it as usual.
        caretOffset = caretRect.flatMap { caret in
            let offset = caret.minY - visibleRect.minY
            return offset >= 0 && offset + caret.height <= visibleRect.height ? offset : nil
        }
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        // Typing only redraws around the new letters, so clear (or bring back) the whole hint.
        if showsPlaceholder != string.isEmpty { needsDisplay = true }
        keepCaretInPlace()
    }

    /// After an edit, scroll so the caret is as far down the screen as it was before, or two thirds down if it was lower.
    private func keepCaretInPlace() {
        guard let offset = caretOffset else { return }
        caretOffset = nil
        guard let scrollView = enclosingScrollView else { return }
        sizeToFit()  // so the page is already as long as the new text
        guard let caret = caretRect else { return }
        let clipView = scrollView.contentView
        var bounds = clipView.bounds
        bounds.origin.y = caret.minY - min(offset, (bounds.height * Self.lowestCaret).rounded())
        let origin = clipView.constrainBoundsRect(bounds).origin
        guard origin != clipView.bounds.origin else { return }
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Where the caret is, in this view's coordinates.
    private var caretRect: NSRect? {
        guard let window else { return nil }
        let onScreen = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        guard onScreen != .zero else { return nil }
        return convert(window.convertFromScreen(onScreen), from: nil)
    }
}

enum Typography {
    static func font(size: Double) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        if let serif = base.fontDescriptor.withDesign(.serif) {
            return NSFont(descriptor: serif, size: size) ?? base
        }
        return base
    }

    static func paragraph(size: Double) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.45
        style.paragraphSpacing = (size * 10 / 18).rounded()  // 10 pt at the default 18
        return style
    }

    static func attributes(size: Double) -> [NSAttributedString.Key: Any] {
        [.font: font(size: size), .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph(size: size)]
    }
}
