//
//  NoteEditorView.swift
//  Tab Note
//

import SwiftUI
import AppKit

struct NoteEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var searchQuery: String
    var noteId: String?
    var searchRequestID: Int
    @ObservedObject var settings: SettingsManager
    var onThemeSelected: ((String) -> Void)?
    var onRTFChange: ((Data?) -> Void)?
    var initialRTF: Data?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = HighlightCapturingTextView()
        textView.onThemeSelected = self.onThemeSelected
        textView.onRichTextChange = { [weak coordinator = context.coordinator] rtf in
            coordinator?.persistRTF(rtf)
        }

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.usesFontPanel = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindPanel = true
        textView.font = settings.selectedFontEnum.nsFont

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        textView.defaultParagraphStyle = paragraphStyle

        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 12, height: 12)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.installStyleObserver(for: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HighlightCapturingTextView else { return }
        context.coordinator.parent = self
        textView.onThemeSelected = self.onThemeSelected
        textView.onRichTextChange = { [weak coordinator = context.coordinator] rtf in
            coordinator?.persistRTF(rtf)
        }

        // Force reload RTF if content string OR noteId tab has changed
        let contentChanged = (textView.string != text)
        let tabChanged = (context.coordinator.lastNoteId != noteId)
        
        if contentChanged || tabChanged {
            context.coordinator.lastNoteId = noteId
            context.coordinator.isProgrammaticUpdate = true
            let cursor = textView.selectedRanges
            if let rtf = initialRTF,
               let attrStr = NSAttributedString(rtf: rtf, documentAttributes: nil) {
                textView.textStorage?.setAttributedString(attrStr)
            } else {
                textView.textStorage?.setAttributedString(
                    NSAttributedString(string: text, attributes: [
                        .font: settings.selectedFontEnum.nsFont,
                        .foregroundColor: NSColor.labelColor
                    ])
                )
            }
            let len = textView.string.count
            let safe = cursor.filter { $0.rangeValue.location + $0.rangeValue.length <= len }
            textView.selectedRanges = safe.isEmpty ? [NSValue(range: NSRange(location: len, length: 0))] : safe
            context.coordinator.isProgrammaticUpdate = false
        }

        // Only enforce typing/insertion colors without destroying existing rich-text spans
        let currentAttrs = textView.typingAttributes
        var newAttrs = currentAttrs
        if currentAttrs[.foregroundColor] == nil {
            newAttrs[.foregroundColor] = NSColor.labelColor
        }
        textView.typingAttributes = newAttrs
        textView.insertionPointColor = NSColor.labelColor

        context.coordinator.updateSearch(in: textView, query: searchQuery, requestID: searchRequestID)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditorView
        weak var textView: NSTextView?
        var lastNoteId: String?
        var isProgrammaticUpdate = false
        var styleObserver: NSObjectProtocol?
        private var lastSearchQuery = ""
        private var lastSearchRequestID = 0

        init(_ parent: NoteEditorView) { self.parent = parent }

        deinit {
            if let styleObserver {
                NotificationCenter.default.removeObserver(styleObserver)
            }
        }

        func installStyleObserver(for textView: HighlightCapturingTextView) {
            if let styleObserver {
                NotificationCenter.default.removeObserver(styleObserver)
            }
            styleObserver = NotificationCenter.default.addObserver(
                forName: .applyTextStyle,
                object: nil,
                queue: .main
            ) { [weak textView] note in
                guard let raw = note.object as? String,
                      let style = TextStyleCommand(rawValue: raw) else { return }
                textView?.apply(style: style)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            guard !isProgrammaticUpdate else { return }
            parent.text = tv.string
            persistRTF(from: tv)
        }

        func persistRTF(_ rtf: Data?) {
            parent.onRTFChange?(rtf)
        }

        private func persistRTF(from textView: NSTextView) {
            guard let storage = textView.textStorage else {
                parent.onRTFChange?(nil)
                return
            }
            let rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:])
            parent.onRTFChange?(rtf)
        }

        func updateSearch(in textView: NSTextView, query: String, requestID: Int) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                lastSearchQuery = ""
                lastSearchRequestID = requestID
                return
            }

            if trimmed != lastSearchQuery {
                lastSearchQuery = trimmed
                lastSearchRequestID = requestID
                _ = selectNextMatch(in: textView, query: trimmed, from: 0, wrap: false)
                return
            }

            guard requestID != lastSearchRequestID else { return }
            lastSearchRequestID = requestID
            let selection = textView.selectedRange()
            let start = selection.location + max(selection.length, 1)
            let found = selectNextMatch(in: textView, query: trimmed, from: start, wrap: true)
            if !found { NSSound.beep() }
        }

        @discardableResult
        private func selectNextMatch(in textView: NSTextView, query: String, from start: Int, wrap: Bool) -> Bool {
            let text = textView.string as NSString
            let totalLength = text.length
            guard totalLength > 0 else { return false }

            let boundedStart = max(0, min(start, totalLength))
            let tailRange = NSRange(location: boundedStart, length: totalLength - boundedStart)
            let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

            var match = text.range(of: query, options: options, range: tailRange)
            if match.location == NSNotFound, wrap, boundedStart > 0 {
                let headRange = NSRange(location: 0, length: boundedStart)
                match = text.range(of: query, options: options, range: headRange)
            }

            guard match.location != NSNotFound else { return false }
            textView.setSelectedRange(match)
            textView.scrollRangeToVisible(match)
            textView.showFindIndicator(for: match)
            return true
        }
    }
}

// MARK: - HighlightCapturingTextView

class HighlightCapturingTextView: NSTextView {

    var onThemeSelected: ((String) -> Void)?
    var onRichTextChange: ((Data?) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu(title: "")

        // — Text Styles —
        menu.addItem(.separator())
        let stylesTitle = NSMenuItem(title: "Text Style", action: nil, keyEquivalent: "")
        stylesTitle.isEnabled = false
        menu.addItem(stylesTitle)

        let styles: [(TextStyleCommand, Selector)] = [
            (.title, #selector(styleTitle(_:))),
            (.heading, #selector(styleHeading(_:))),
            (.subheading, #selector(styleSubheading(_:))),
            (.body, #selector(styleBody(_:))),
            (.bulletedList, #selector(styleBullet(_:))),
            (.dashedList, #selector(styleDash(_:))),
            (.numberedList, #selector(styleNumbered(_:))),
        ]
        for (style, sel) in styles {
            let item = NSMenuItem(title: style.menuTitle, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        // — Theme —
        menu.addItem(.separator())
        menu.addItem(ThemeMenuHelper.createThemeMenuItem(target: self, action: #selector(themeBtnClicked(_:))))

        return menu
    }

    @objc private func themeBtnClicked(_ sender: NSButton) {
        if let hex = sender.identifier?.rawValue { onThemeSelected?(hex) }
    }

    // MARK: - Text Style Actions

    @objc private func styleTitle(_ sender: Any?) {
        apply(style: .title)
    }
    @objc private func styleHeading(_ sender: Any?) {
        apply(style: .heading)
    }
    @objc private func styleSubheading(_ sender: Any?) {
        apply(style: .subheading)
    }
    @objc private func styleBody(_ sender: Any?) {
        apply(style: .body)
    }
    @objc private func styleBullet(_ sender: Any?) {
        apply(style: .bulletedList)
    }
    @objc private func styleDash(_ sender: Any?) {
        apply(style: .dashedList)
    }
    @objc private func styleNumbered(_ sender: Any?) {
        apply(style: .numberedList)
    }

    func apply(style: TextStyleCommand) {
        switch style {
        case .title:
            applyStyle(fontSize: 26, bold: true)
        case .heading:
            applyStyle(fontSize: 20, bold: true)
        case .subheading:
            applyStyle(fontSize: 16, bold: true)
        case .body:
            applyStyle(fontSize: 13, bold: false)
        case .bulletedList:
            insertListPrefix("• ")
        case .dashedList:
            insertListPrefix("— ")
        case .numberedList:
            insertNumberedListPrefix()
        }
    }

    private func applyStyle(fontSize: CGFloat, bold: Bool) {
        guard let storage = textStorage else { return }
        let selection = selectedRange()
        let line = lineRange(at: selection.location)
        let range = selection.length > 0 ? selection : line
        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let font = bold ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask) : baseFont
        if range.length > 0 {
            let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            replacement.addAttribute(.font, value: font, range: NSRange(location: 0, length: replacement.length))
            replaceAttributedRangeWithUndo(
                range: range,
                replacement: replacement,
                actionName: "Apply Style",
                preserveSelection: selection
            )
        }
        var attrs = typingAttributes
        attrs[.font] = font
        typingAttributes = attrs
    }

    private func insertListPrefix(_ prefix: String) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        let fullText = storage.string as NSString
        let lineRange = fullText.lineRange(for: range)
        let lineText = fullText.substring(with: lineRange)
        guard shouldChangeText(in: lineRange, replacementString: prefixed(lineText, with: prefix)) else { return }
        let attrs = typingAttributes
        // Prefix each line
        let lines = lineText.components(separatedBy: "\n")
        let prefixed = lines.map { line -> String in
            if line.isEmpty { return line }
            // strip existing prefix before adding new one
            let stripped = line.trimmingLeadingPrefix()
            return prefix + stripped
        }.joined(separator: "\n")
        storage.replaceCharacters(in: lineRange, with: NSAttributedString(string: prefixed, attributes: attrs))
        didChangeText()
        notifyRichTextChange()
    }

    private func prefixed(_ lineText: String, with prefix: String) -> String {
        let lines = lineText.components(separatedBy: "\n")
        return lines.map { line -> String in
            if line.isEmpty { return line }
            return prefix + line.trimmingLeadingPrefix()
        }.joined(separator: "\n")
    }

    private func insertNumberedListPrefix() {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        let fullText = storage.string as NSString
        let lineRange = fullText.lineRange(for: range)
        let lineText = fullText.substring(with: lineRange)
        guard shouldChangeText(in: lineRange, replacementString: numbered(lineText)) else { return }
        let attrs = typingAttributes
        let lines = lineText.components(separatedBy: "\n")
        var counter = 1
        let prefixed = lines.map { line -> String in
            if line.isEmpty { return line }
            let stripped = line.trimmingLeadingPrefix()
            let result = "\(counter). \(stripped)"
            counter += 1
            return result
        }.joined(separator: "\n")
        storage.replaceCharacters(in: lineRange, with: NSAttributedString(string: prefixed, attributes: attrs))
        didChangeText()
        notifyRichTextChange()
    }

    private func numbered(_ lineText: String) -> String {
        let lines = lineText.components(separatedBy: "\n")
        var counter = 1
        return lines.map { line -> String in
            if line.isEmpty { return line }
            let result = "\(counter). \(line.trimmingLeadingPrefix())"
            counter += 1
            return result
        }.joined(separator: "\n")
    }

    private func lineRange(at location: Int) -> NSRange {
        let str = string as NSString
        let full = NSRange(location: 0, length: str.length)
        var lineRange = NSRange()
        str.getLineStart(nil, end: nil, contentsEnd: nil, for: NSRange(location: min(location, str.length), length: 0))
        lineRange = str.lineRange(for: NSRange(location: min(location, str.length), length: 0))
        return NSIntersectionRange(lineRange, full)
    }

    // MARK: - Plain-text paste

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let plain = pb.string(forType: .string) else { return }
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: plain) else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: typingAttributes[.font] ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: typingAttributes[.foregroundColor] ?? NSColor.labelColor
        ]
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: plain, attributes: attrs))
        let newLoc = range.location + (plain as NSString).length
        setSelectedRange(NSRange(location: newLoc, length: 0))
        didChangeText()
        notifyRichTextChange()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "b":
            toggleTrait(.boldFontMask)
            return true
        case "i":
            toggleTrait(.italicFontMask)
            return true
        case "u":
            applyHighlight()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        if range.length == 0 {
            let fm = NSFontManager.shared
            let currentFont = typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 13)
            let newFont = fm.traits(of: currentFont).contains(trait)
                ? fm.convert(currentFont, toNotHaveTrait: trait)
                : fm.convert(currentFont, toHaveTrait: trait)
            var attrs = typingAttributes
            attrs[.font] = newFont
            typingAttributes = attrs
            return
        }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        replacement.enumerateAttribute(.font, in: NSRange(location: 0, length: replacement.length)) { value, subRange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let fm = NSFontManager.shared
            let newFont = fm.traits(of: font).contains(trait)
                ? fm.convert(font, toNotHaveTrait: trait)
                : fm.convert(font, toHaveTrait: trait)
            replacement.addAttribute(.font, value: newFont, range: subRange)
        }
        replaceAttributedRangeWithUndo(
            range: range,
            replacement: replacement,
            actionName: trait == .boldFontMask ? "Toggle Bold" : "Toggle Italic",
            preserveSelection: range
        )
    }

    private func applyHighlight() {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let existing = replacement.attribute(.backgroundColor, at: 0, effectiveRange: nil)
        if existing != nil {
            replacement.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: replacement.length))
        } else {
            replacement.addAttribute(
                .backgroundColor,
                value: NSColor.systemYellow.withAlphaComponent(0.55),
                range: NSRange(location: 0, length: replacement.length)
            )
        }
        replaceAttributedRangeWithUndo(
            range: range,
            replacement: replacement,
            actionName: "Toggle Highlight",
            preserveSelection: range
        )
    }

    private func replaceAttributedRangeWithUndo(
        range: NSRange,
        replacement: NSAttributedString,
        actionName: String,
        preserveSelection: NSRange
    ) {
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        let safeRange = NSIntersectionRange(range, full)
        guard safeRange.length == range.length else { return }

        let previous = storage.attributedSubstring(from: safeRange)
        let previousSelection = selectedRange()

        storage.beginEditing()
        storage.replaceCharacters(in: safeRange, with: replacement)
        storage.endEditing()

        let replacementRange = NSRange(location: safeRange.location, length: replacement.length)
        let maxCursor = storage.length
        let safeSelection = NSRange(
            location: min(preserveSelection.location, maxCursor),
            length: min(preserveSelection.length, max(0, maxCursor - min(preserveSelection.location, maxCursor)))
        )
        setSelectedRange(safeSelection)

        didChangeText()
        notifyRichTextChange()

        undoManager?.registerUndo(withTarget: self) { target in
            target.replaceAttributedRangeWithUndo(
                range: replacementRange,
                replacement: previous,
                actionName: actionName,
                preserveSelection: previousSelection
            )
        }
        undoManager?.setActionName(actionName)
    }

    private func notifyRichTextChange() {
        guard let storage = textStorage else {
            onRichTextChange?(nil)
            return
        }
        let rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:])
        onRichTextChange?(rtf)
    }
}

// MARK: - String helper

private extension String {
    func trimmingLeadingPrefix() -> String {
        // Strip common list prefixes: "• ", "— ", "- ", "* ", "N. "
        let patterns = ["^\\d+\\.\\s*", "^[•\\-—\\*]\\s*"]
        var result = self
        for pattern in patterns {
            if let range = result.range(of: pattern, options: .regularExpression) {
                result.removeSubrange(range)
                break
            }
        }
        return result
    }
}
