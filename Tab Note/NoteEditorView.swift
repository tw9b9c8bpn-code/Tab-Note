//
//  NoteEditorView.swift
//  Tab Note
//

import SwiftUI
import AppKit

struct NoteEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var searchQuery: String
    var windowID: String
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
        textView.linkTextAttributes = [
            .underlineStyle: 0,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

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
        context.coordinator.installInlineQuestionObserver(for: textView)
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
            if tabChanged {
                context.coordinator.resetFontChoiceTracking()
                textView.dismissInlineAnswerPopover()
            }
            context.coordinator.isProgrammaticUpdate = true
            let cursor = textView.selectedRanges
            if let rtf = initialRTF,
               let attrStr = NSAttributedString(rtf: rtf, documentAttributes: nil) {
                textView.textStorage?.setAttributedString(
                    HighlightCapturingTextView.removingInlineAnswerMarkers(from: attrStr)
                )
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
        context.coordinator.applyAppearanceIfNeeded(
            to: textView,
            isDarkMode: settings.isDarkMode,
            force: contentChanged || tabChanged
        )
        context.coordinator.applyFontChoiceIfNeeded(to: textView, choice: settings.selectedFontEnum, force: tabChanged)

        context.coordinator.updateSearch(in: textView, query: searchQuery, requestID: searchRequestID)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditorView
        weak var textView: HighlightCapturingTextView?
        var lastNoteId: String?
        var isProgrammaticUpdate = false
        var styleObserver: NSObjectProtocol?
        var inlineQuestionObserver: NSObjectProtocol?
        private var lastSearchQuery = ""
        private var lastSearchRequestID = 0
        private var pendingTripleQuestionTrigger = false
        private var pendingInlineTriggerLocation: Int?
        private var inlineAnswerInFlight = false
        private var lastAppliedFontChoice: FontChoice?
        private var lastAppliedDarkMode: Bool?

        init(_ parent: NoteEditorView) { self.parent = parent }

        deinit {
            if let styleObserver {
                NotificationCenter.default.removeObserver(styleObserver)
            }
            if let inlineQuestionObserver {
                NotificationCenter.default.removeObserver(inlineQuestionObserver)
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

        func installInlineQuestionObserver(for textView: HighlightCapturingTextView) {
            if let inlineQuestionObserver {
                NotificationCenter.default.removeObserver(inlineQuestionObserver)
            }
            inlineQuestionObserver = NotificationCenter.default.addObserver(
                forName: .answerQuestionAtCursor,
                object: nil,
                queue: .main
            ) { [weak self, weak textView] note in
                guard let self, let textView else { return }
                if let targetWindowID = note.object as? String,
                   targetWindowID != self.parent.windowID {
                    return
                }
                self.requestInlineAnswer(in: textView)
            }
        }

        func textView(_ textView: NSTextView,
                      shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard !isProgrammaticUpdate else { return true }
            defer {
                if replacementString != "?" {
                    pendingTripleQuestionTrigger = false
                    pendingInlineTriggerLocation = nil
                }
            }

            guard replacementString == "?", affectedCharRange.length == 0 else { return true }
            let nsText = textView.string as NSString
            guard affectedCharRange.location >= 2 else { return true }
            let prevTwoRange = NSRange(location: affectedCharRange.location - 2, length: 2)
            let prevTwo = nsText.substring(with: prevTwoRange)
            guard prevTwo == "??" else { return true }

            if affectedCharRange.location >= 3 {
                let prevThree = nsText.character(at: affectedCharRange.location - 3)
                if prevThree == UInt16(UnicodeScalar("?").value) { return true }
            }

            pendingTripleQuestionTrigger = true
            pendingInlineTriggerLocation = affectedCharRange.location + 1
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            guard !isProgrammaticUpdate else { return }
            parent.text = tv.string
            persistRTF(from: tv)

            if pendingTripleQuestionTrigger, let richTextView = tv as? HighlightCapturingTextView {
                pendingTripleQuestionTrigger = false
                let triggerLocation = pendingInlineTriggerLocation
                pendingInlineTriggerLocation = nil
                DispatchQueue.main.async { [weak self, weak richTextView] in
                    guard let self, let richTextView else { return }
                    self.requestInlineAnswer(in: richTextView, preferredLocation: triggerLocation)
                }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !isProgrammaticUpdate else { return false }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), inlineAnswerInFlight {
                inlineAnswerInFlight = false
                AIService.shared.cancelCurrentRequest()
                publishInlineAIStatus("Cancelled", inFlight: false)
                return true
            }
            guard commandSelector == #selector(NSResponder.insertTab(_:)) else { return false }
            let range = textView.selectedRange()
            guard range.length == 0, range.location > 0 else { return false }
            let nsText = textView.string as NSString
            let previous = nsText.substring(with: NSRange(location: range.location - 1, length: 1))
            guard previous == "?" else { return false }
            if let richTextView = textView as? HighlightCapturingTextView {
                let triggerLocation = range.location
                DispatchQueue.main.async { [weak self, weak richTextView] in
                    guard let self, let richTextView else { return }
                    self.requestInlineAnswer(in: richTextView, preferredLocation: triggerLocation)
                }
            }
            return true
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

        private struct ParagraphContext {
            let paragraph: String
            let insertionLocation: Int
        }

        private func requestInlineAnswer(in textView: HighlightCapturingTextView, preferredLocation: Int? = nil) {
            guard !inlineAnswerInFlight else {
                publishInlineAIStatus("AI is already answering...", inFlight: true)
                return
            }
            guard let context = currentParagraphContext(in: textView) else {
                publishInlineAIStatus("No paragraph at cursor", inFlight: false)
                NSSound.beep()
                return
            }
            let requestNoteID = parent.noteId
            inlineAnswerInFlight = true
            publishInlineAIStatus("Reading paragraph...", inFlight: true)

            AIService.shared.answerQuestionSentence(
                sentence: context.paragraph,
                settings: parent.settings,
                onStatus: { [weak self] status in
                    DispatchQueue.main.async {
                        self?.publishInlineAIStatus(status, inFlight: true)
                    }
                },
                completion: { [weak self, weak textView] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.inlineAnswerInFlight = false
                        guard let textView else { return }
                        guard self.parent.noteId == requestNoteID else {
                            self.publishInlineAIStatus("Inline answer cancelled", inFlight: false)
                            return
                        }
                        switch result {
                        case .success(let raw):
                            let answer = self.normalizeInlineAnswer(raw)
                            guard !answer.isEmpty else {
                                self.publishInlineAIStatus("No answer generated", inFlight: false)
                                NSSound.beep()
                                return
                            }
                            textView.insertInlineAnswerMarkerAndShowPopover(
                                answer,
                                summaryChip: self.parent.settings.aiPromptSummaryChip,
                                aiMode: self.parent.settings.aiModeEnum,
                                model: self.parent.settings.aiModel,
                                preferredLocation: preferredLocation ?? context.insertionLocation
                            )
                            self.publishInlineAIStatus("Answer ready", inFlight: false)
                        case .failure(let error):
                            if let aiError = error as? AIService.AIError, case .cancelled = aiError {
                                self.publishInlineAIStatus("Cancelled", inFlight: false)
                            } else {
                                self.publishInlineAIStatus("Error: \(error.localizedDescription)", inFlight: false)
                            }
                        }
                    }
                }
            )
        }

        private func currentParagraphContext(in textView: NSTextView) -> ParagraphContext? {
            let nsText = textView.string as NSString
            let totalLength = nsText.length
            guard totalLength > 0 else { return nil }

            let selection = textView.selectedRange()
            let anchor = max(0, min(selection.location == totalLength ? totalLength - 1 : selection.location, totalLength - 1))
            let paragraphRange = nsText.paragraphRange(for: NSRange(location: anchor, length: 0))
            let insertionLocation = inlineAnswerInsertionLocation(
                in: textView,
                selection: selection,
                paragraphRange: paragraphRange
            )
            let rawParagraph: String
            if let richTextView = textView as? HighlightCapturingTextView {
                rawParagraph = richTextView.cleanedParagraphString(in: paragraphRange)
            } else {
                rawParagraph = nsText.substring(with: paragraphRange)
            }
            let cleanedParagraph = stripTrailingAITrigger(from: rawParagraph)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedParagraph.isEmpty else { return nil }
            return ParagraphContext(paragraph: cleanedParagraph, insertionLocation: insertionLocation)
        }

        private func inlineAnswerInsertionLocation(
            in textView: NSTextView,
            selection: NSRange,
            paragraphRange: NSRange
        ) -> Int {
            let nsText = textView.string as NSString
            let totalLength = nsText.length
            let safeLocation = max(0, min(selection.location, totalLength))

            if safeLocation > 0, nsText.character(at: safeLocation - 1) == UInt16(UnicodeScalar("?").value) {
                return safeLocation
            }

            let paragraphText = nsText.substring(with: paragraphRange)
            let paragraphNSString = paragraphText as NSString
            let paragraphFullRange = NSRange(location: 0, length: paragraphNSString.length)
            let triggerRange = paragraphNSString.range(
                of: #"\?{1,3}\s*$"#,
                options: .regularExpression,
                range: paragraphFullRange
            )
            guard triggerRange.location != NSNotFound else { return safeLocation }

            let questionOnlyRange = paragraphNSString.range(
                of: #"\?+$"#,
                options: .regularExpression,
                range: triggerRange
            )
            guard questionOnlyRange.location != NSNotFound else {
                return paragraphRange.location + triggerRange.location + triggerRange.length
            }
            return paragraphRange.location + questionOnlyRange.location + questionOnlyRange.length
        }

        private func normalizeInlineAnswer(_ raw: String) -> String {
            var text = raw
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Restore common missing spacing around punctuation from model output.
            text = text.replacingOccurrences(of: #":(?=[A-Za-z])"#, with: ": ", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\*\*([^*\n]{1,80}?):\s*\*\*"#, with: "**$1:**", options: .regularExpression)
            text = text.replacingOccurrences(of: #"([^\s\n])(?=\*\*)"#, with: "$1 ", options: .regularExpression)
            text = text.replacingOccurrences(of: #"(\*\*[^*\n]+\*\*)(?=[A-Za-z0-9])"#, with: "$1 ", options: .regularExpression)

            // Only split before speaker/label-style bold markers (e.g. "**Maya:**"),
            // not generic inline bold spans.
            text = text.replacingOccurrences(
                of: #"(?<!^)(?<!\n)\s*(\*\*[A-Za-z][^*\n]{0,60}:\*\*)"#,
                with: "\n\n$1",
                options: .regularExpression
            )

            // If the model returns a wall of text, split long prose into paragraphs.
            if !text.contains("\n\n"), text.count > 220 {
                text = text.replacingOccurrences(
                    of: #"([.!?])\s+(?=[A-Z])"#,
                    with: "$1\n\n",
                    options: .regularExpression
                )
            }

            text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func publishInlineAIStatus(_ status: String, inFlight: Bool) {
            NotificationCenter.default.post(
                name: .inlineAIStatusDidChange,
                object: parent.windowID,
                userInfo: [
                    "status": status,
                    "inFlight": inFlight
                ]
            )
        }

        private func stripTrailingAITrigger(from text: String) -> String {
            text.replacingOccurrences(of: #"\?{3}\s*$"#, with: "", options: .regularExpression)
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

        func resetFontChoiceTracking() {
            lastAppliedFontChoice = nil
        }

        func applyAppearanceIfNeeded(to textView: HighlightCapturingTextView, isDarkMode: Bool, force: Bool = false) {
            if !force, lastAppliedDarkMode == isDarkMode { return }
            lastAppliedDarkMode = isDarkMode

            let appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
            textView.appearance = appearance
            textView.enclosingScrollView?.appearance = appearance
            textView.textColor = NSColor.labelColor
            textView.insertionPointColor = NSColor.labelColor
            textView.linkTextAttributes = [
                .underlineStyle: 0,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            normalizeVisibleTextColors(in: textView)
        }

        private func normalizeVisibleTextColors(in textView: HighlightCapturingTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return }

            var plainTextRanges: [NSRange] = []
            var markerRanges: [NSRange] = []
            storage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
                if attributes[.attachment] != nil { return }
                if let link = attributes[.link],
                   HighlightCapturingTextView.inlineAnswerMarkerLinkString(from: link) != nil {
                    markerRanges.append(range)
                    return
                }
                plainTextRanges.append(range)
            }

            storage.beginEditing()
            for range in markerRanges {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }
            for range in plainTextRanges {
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
            storage.endEditing()
        }

        func applyFontChoiceIfNeeded(to textView: HighlightCapturingTextView, choice: FontChoice, force: Bool = false) {
            if !force, lastAppliedFontChoice == choice { return }
            lastAppliedFontChoice = choice
            let previousFlag = isProgrammaticUpdate
            isProgrammaticUpdate = true
            textView.applyFontFamily(choice)
            isProgrammaticUpdate = previousFlag
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
    private var inlineAnswerPanel: NSPanel?
    private static let inlineAnswerMarkerPrefix = "tabnote-ai:"

    private struct InlineAnswerPayload: Codable {
        let answer: String
        let summaryChip: String
        let aiModeRawValue: String
        let model: String

        init(answer: String, summaryChip: String, aiMode: AIMode, model: String) {
            self.answer = answer
            self.summaryChip = summaryChip
            self.aiModeRawValue = aiMode.rawValue
            self.model = model
        }

        var aiMode: AIMode {
            AIMode(rawValue: aiModeRawValue) ?? .local
        }
    }

    deinit {
        inlineAnswerPanel?.close()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let markerContext = inlineAnswerMarkerContext(at: event) {
            let menu = NSMenu(title: "")
            let showItem = NSMenuItem(title: "Show AI Response", action: #selector(showInlineAnswerFromMenu(_:)), keyEquivalent: "")
            showItem.target = self
            showItem.tag = markerContext.charIndex
            showItem.representedObject = markerContext.link as NSString
            menu.addItem(showItem)

            let deleteItem = NSMenuItem(title: "Delete AI Marker", action: #selector(deleteInlineAnswerMarkerFromMenu(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.tag = markerContext.charIndex
            menu.addItem(deleteItem)
            return menu
        }

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

    @objc private func showInlineAnswerFromMenu(_ sender: NSMenuItem) {
        _ = showInlineAnswerPopover(fromMarkerLink: sender.representedObject, at: sender.tag)
    }

    @objc private func deleteInlineAnswerMarkerFromMenu(_ sender: NSMenuItem) {
        deleteInlineAnswerMarker(at: sender.tag)
    }

    func insertInlineAnswerMarkerAndShowPopover(
        _ answer: String,
        summaryChip: String,
        aiMode: AIMode,
        model: String,
        preferredLocation: Int
    ) {
        let answerText = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answerText.isEmpty else { return }
        let payload = InlineAnswerPayload(
            answer: answerText,
            summaryChip: summaryChip,
            aiMode: aiMode,
            model: model
        )
        let anchorCharacterIndex = max(
            0,
            min(preferredLocation, max(0, (string as NSString).length - 1))
        )
        showInlineAnswerPopover(payload: payload, anchorCharacterIndex: anchorCharacterIndex)
    }

    func dismissInlineAnswerPopover() {
        closeInlineAnswerPopover()
    }

    private func closeInlineAnswerPopover() {
        inlineAnswerPanel?.orderOut(nil)
        inlineAnswerPanel?.close()
        inlineAnswerPanel = nil
    }

    private func showInlineAnswerPopover(payload: InlineAnswerPayload, anchorCharacterIndex: Int) {
        closeInlineAnswerPopover()
        let anchor = characterRect(for: anchorCharacterIndex)
        presentInlineAnswerPopover(payload: payload, anchorRect: anchor)
    }

    private func presentInlineAnswerPopover(payload: InlineAnswerPayload, anchorRect: NSRect) {
        let preparedAnswer = InlineCursorAnswerPopoverView.preparedAnswerText(from: payload.answer)
        let renderedAnswer = InlineCursorAnswerPopoverView.renderedAttributedString(from: preparedAnswer)
        let metrics = InlineCursorAnswerPopoverView.responseMetrics(
            for: preparedAnswer,
            aiMode: payload.aiMode,
            model: payload.model
        )
        let size = popoverSize(for: renderedAnswer)
        let view = InlineCursorAnswerPopoverView(
            renderedAnswer: renderedAnswer,
            summaryChip: payload.summaryChip,
            metrics: metrics,
            model: payload.model,
            contentSize: size
        )
        let host = NSHostingController(rootView: view)
        let panel = ActivatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: SettingsManager.shared.isDarkMode ? .darkAqua : .aqua)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = host
        panel.contentMinSize = NSSize(width: 220, height: 120)
        panel.contentMaxSize = NSSize(width: 380, height: 600)

        let screenFrame = window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchorOnWindow = convert(anchorRect, to: nil)
        let anchorOnScreen = window?.convertToScreen(anchorOnWindow) ?? anchorOnWindow
        let x = min(screenFrame.maxX - size.width - 16, anchorOnScreen.maxX + 10)
        let idealY = anchorOnScreen.maxY - (size.height * 0.18)
        let y = max(screenFrame.minY + 24, min(screenFrame.maxY - size.height - 24, idealY))
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        panel.makeKeyAndOrderFront(nil)
        inlineAnswerPanel = panel
    }

    private func caretAnchorRect() -> NSRect {
        let selection = selectedRange()
        guard let lm = layoutManager, let tc = textContainer else {
            return NSRect(x: textContainerInset.width, y: textContainerInset.height, width: 1, height: 16)
        }
        guard lm.numberOfGlyphs > 0 else {
            return NSRect(x: textContainerInset.width, y: textContainerInset.height, width: 1, height: 16)
        }
        let location = max(0, min(selection.location, (string as NSString).length))
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: location, length: 0), actualCharacterRange: nil)
        let glyphIndex = min(glyphRange.location, lm.numberOfGlyphs - 1)
        var rect = lm.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: tc)
        if rect.isNull || rect.isInfinite || rect.height <= 0 {
            rect = NSRect(x: textContainerInset.width, y: textContainerInset.height, width: 1, height: 16)
        }
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        rect.size.width = max(rect.width, 1)
        rect.size.height = max(rect.height, 16)
        return rect
    }

    private func characterRect(for charIndex: Int) -> NSRect {
        guard let lm = layoutManager, let tc = textContainer, lm.numberOfGlyphs > 0 else {
            return caretAnchorRect()
        }
        let safeIndex = max(0, min(charIndex, max(0, (string as NSString).length - 1)))
        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: safeIndex, length: 1), actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        if rect.isNull || rect.isInfinite || rect.height <= 0 {
            return caretAnchorRect()
        }
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        rect.size.width = max(rect.width, 12)
        rect.size.height = max(rect.height, 16)
        return rect
    }

    private func characterIndex(at pointInView: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, (string as NSString).length > 0 else { return nil }
        let containerPoint = NSPoint(
            x: pointInView.x - textContainerInset.width,
            y: pointInView.y - textContainerInset.height
        )
        let glyphIndex = lm.glyphIndex(for: containerPoint, in: tc)
        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < (string as NSString).length else { return nil }
        return charIndex
    }

    private func inlineAnswerMarkerContext(at event: NSEvent) -> (link: String, charIndex: Int)? {
        let point = convert(event.locationInWindow, from: nil)
        guard let charIndex = characterIndex(at: point),
              let storage = textStorage else { return nil }
        let link = storage.attribute(.link, at: charIndex, effectiveRange: nil)
        guard let linkString = Self.inlineAnswerMarkerLinkString(from: link) else { return nil }
        return (linkString, charIndex)
    }

    private func insertInlineAnswerMarker(payload: InlineAnswerPayload, preferredLocation: Int) -> Int {
        guard let marker = markerAttributedString(for: payload), let storage = textStorage else {
            return selectedRange().location
        }
        let safeLocation = resolvedMarkerInsertionLocation(from: max(0, min(preferredLocation, storage.length)))
        let insertionRange = NSRange(location: safeLocation, length: 0)
        let nextSelection = NSRange(location: safeLocation + marker.length, length: 0)
        replaceAttributedRangeWithUndo(
            range: insertionRange,
            replacement: marker,
            actionName: "Insert AI Marker",
            preserveSelection: nextSelection
        )
        return safeLocation
    }

    private func markerAttributedString(for payload: InlineAnswerPayload) -> NSAttributedString? {
        guard let link = Self.inlineAnswerMarkerLink(for: payload) else { return nil }
        let attachment = NSTextAttachment()
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        attachment.image = NSImage(
            systemSymbolName: "info.circle.fill",
            accessibilityDescription: "AI response"
        )?.withSymbolConfiguration(config)
        attachment.bounds = NSRect(x: 0, y: -2, width: 16, height: 16)
        let marker = NSMutableAttributedString(attachment: attachment)
        marker.addAttributes(
            [
                .link: link,
                .foregroundColor: NSColor.secondaryLabelColor
            ],
            range: NSRange(location: 0, length: marker.length)
        )
        return marker
    }

    private func showInlineAnswerPopover(fromMarkerLink link: Any?, at charIndex: Int) -> Bool {
        guard let payload = Self.inlineAnswerPayload(from: link) else { return false }
        showInlineAnswerPopover(payload: payload, anchorCharacterIndex: charIndex)
        return true
    }

    private func deleteInlineAnswerMarker(at charIndex: Int) {
        guard let storage = textStorage, charIndex >= 0, charIndex < storage.length else { return }
        var range = NSRange(location: 0, length: 0)
        let link = storage.attribute(.link, at: charIndex, effectiveRange: &range)
        guard Self.inlineAnswerMarkerLinkString(from: link) != nil else { return }
        closeInlineAnswerPopover()
        replaceAttributedRangeWithUndo(
            range: range,
            replacement: NSAttributedString(string: ""),
            actionName: "Delete AI Marker",
            preserveSelection: NSRange(location: range.location, length: 0)
        )
    }

    func cleanedParagraphString(in range: NSRange) -> String {
        guard let storage = textStorage else {
            return (string as NSString).substring(with: range)
        }
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        let attributed = storage.attributedSubstring(from: safeRange)
        let nsString = attributed.string as NSString
        let fullRange = NSRange(location: 0, length: attributed.length)
        let result = NSMutableString()
        attributed.enumerateAttributes(in: fullRange, options: []) { attributes, subRange, _ in
            if Self.inlineAnswerMarkerLinkString(from: attributes[.link]) != nil {
                return
            }
            result.append(nsString.substring(with: subRange))
        }
        return result as String
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        if !showInlineAnswerPopover(fromMarkerLink: link, at: charIndex) {
            super.clicked(onLink: link, at: charIndex)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let markerContext = inlineAnswerMarkerContext(at: event),
           showInlineAnswerPopover(fromMarkerLink: markerContext.link, at: markerContext.charIndex) {
            return
        }
        super.mouseDown(with: event)
    }

    private static func inlineAnswerMarkerLink(for payload: InlineAnswerPayload) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return inlineAnswerMarkerPrefix + base64URLString(from: data)
    }

    static func inlineAnswerMarkerLinkString(from link: Any?) -> String? {
        if let string = link as? String, string.hasPrefix(inlineAnswerMarkerPrefix) {
            return string
        }
        if let url = link as? URL {
            let string = url.absoluteString
            return string.hasPrefix(inlineAnswerMarkerPrefix) ? string : nil
        }
        return nil
    }

    static func removingInlineAnswerMarkers(from attributedString: NSAttributedString) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let nsString = attributedString.string as NSString
        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            if inlineAnswerMarkerLinkString(from: attributes[.link]) != nil {
                return
            }
            output.append(
                NSAttributedString(
                    string: nsString.substring(with: range),
                    attributes: attributes
                )
            )
        }
        return output
    }

    private static func inlineAnswerPayload(from link: Any?) -> InlineAnswerPayload? {
        guard let linkString = inlineAnswerMarkerLinkString(from: link) else { return nil }
        let encoded = String(linkString.dropFirst(inlineAnswerMarkerPrefix.count))
        guard let data = dataFromBase64URLString(encoded),
              let payload = try? JSONDecoder().decode(InlineAnswerPayload.self, from: data) else {
            return nil
        }
        return payload
    }

    private static func base64URLString(from data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func dataFromBase64URLString(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private func resolvedMarkerInsertionLocation(from preferredLocation: Int) -> Int {
        guard let storage = textStorage else { return preferredLocation }
        var location = preferredLocation
        while location < storage.length {
            var range = NSRange(location: 0, length: 0)
            let link = storage.attribute(.link, at: location, effectiveRange: &range)
            guard Self.inlineAnswerMarkerLinkString(from: link) != nil,
                  range.location == location,
                  range.length > 0 else {
                break
            }
            location = range.location + range.length
        }
        return location
    }

    private func popoverSize(for attributedText: NSAttributedString) -> NSSize {
        let candidateWidths: [CGFloat]
        switch attributedText.string.count {
        case 0...70:
            candidateWidths = [220, 250, 280]
        case 71...160:
            candidateWidths = [250, 290, 330]
        case 161...320:
            candidateWidths = [280, 320, 360]
        default:
            candidateWidths = [300, 340, 380]
        }

        let chromeHeight: CGFloat = 92
        let minHeight: CGFloat = 120
        let maxHeight: CGFloat = 600

        var bestWidth = candidateWidths.last ?? 380
        var bestHeight = maxHeight
        var smallestOverflow = CGFloat.greatestFiniteMagnitude

        for width in candidateWidths {
            let contentWidth = max(164, width - 28)
            let measured = attributedText.boundingRect(
                with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let targetHeight = chromeHeight + ceil(measured.height)
            if targetHeight <= maxHeight {
                return NSSize(width: width, height: max(minHeight, targetHeight))
            }
            let overflow = targetHeight - maxHeight
            if overflow < smallestOverflow {
                smallestOverflow = overflow
                bestWidth = width
                bestHeight = maxHeight
            }
        }

        return NSSize(width: bestWidth, height: bestHeight)
    }

    func applyFontFamily(_ choice: FontChoice) {
        guard let storage = textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            var attrs = typingAttributes
            attrs[.font] = choice.nsFont
            typingAttributes = attrs
            font = choice.nsFont
            return
        }

        let rewritten = NSMutableAttributedString(attributedString: storage)
        rewritten.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let source = (value as? NSFont) ?? choice.nsFont
            rewritten.addAttribute(.font, value: self.mappedFont(from: source, choice: choice), range: range)
        }

        storage.beginEditing()
        storage.setAttributedString(rewritten)
        storage.endEditing()

        let typingSource = (typingAttributes[.font] as? NSFont) ?? choice.nsFont
        var attrs = typingAttributes
        attrs[.font] = mappedFont(from: typingSource, choice: choice)
        typingAttributes = attrs
        font = mappedFont(from: typingSource, choice: choice)
        didChangeText()
        notifyRichTextChange()
    }

    private func mappedFont(from source: NSFont, choice: FontChoice) -> NSFont {
        let size = max(8, source.pointSize)
        let traits = NSFontManager.shared.traits(of: source)
        let isBold = traits.contains(.boldFontMask)
        let isItalic = traits.contains(.italicFontMask)

        var base: NSFont
        switch choice {
        case .sansSerif:
            base = NSFont.systemFont(ofSize: size, weight: isBold ? .semibold : .regular)
        case .serif:
            base = NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size)
            if isBold {
                base = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
            }
        case .monospace:
            base = NSFont.monospacedSystemFont(ofSize: size, weight: isBold ? .semibold : .regular)
        }

        if isItalic {
            base = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        }
        return base
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

private struct InlineCursorAnswerPopoverView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showPricingPopover = false

    struct ResponseMetrics {
        let words: Int
        let tokens: Int
        let estimatedCost: Double
    }

    let renderedAnswer: NSAttributedString
    let summaryChip: String
    let metrics: ResponseMetrics
    let model: String
    let contentSize: NSSize

    static func preparedAnswerText(from raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        text = text.replacingOccurrences(of: #":(?=[A-Za-z])"#, with: ": ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\*\*([^*\n]{1,80}?):\s*\*\*"#, with: "**$1:**", options: .regularExpression)
        text = text.replacingOccurrences(of: #"([^\s\n])(?=\*\*)"#, with: "$1 ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(\*\*[^*\n]+\*\*)(?=[A-Za-z0-9])"#, with: "$1 ", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"(?<!^)(?<!\n)\s*(\*\*[A-Za-z][^*\n]{0,80}:\*\*)"#,
            with: "\n\n$1",
            options: .regularExpression
        )

        if !text.contains("\n\n"), text.count > 220 {
            text = text.replacingOccurrences(
                of: #"([.!?])\s+(?=[A-Z])"#,
                with: "$1\n\n",
                options: .regularExpression
            )
        }

        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func responseMetrics(for text: String, aiMode: AIMode, model: String) -> ResponseMetrics {
        let words = max(1, text.split(whereSeparator: \.isWhitespace).count)
        let nonWhitespaceChars = text.filter { !$0.isWhitespace }.count
        let byChars = Int(ceil(Double(nonWhitespaceChars) / 4.0))
        let byWords = Int(ceil(Double(words) * 1.33))
        let tokens = max(1, max(byChars, byWords))
        let ratePerMillion = estimatedOutputRatePerMillionTokens(for: model)
        let estimatedCost = aiMode == .local
            ? 0
            : (Double(tokens) * ratePerMillion) / 1_000_000.0
        return ResponseMetrics(words: words, tokens: tokens, estimatedCost: estimatedCost)
    }

    static func renderedAttributedString(from raw: String) -> NSAttributedString {
        let prepared = preparedAnswerText(from: raw)
        let blocks = prepared
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let output = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: "\n\n", attributes: bodyAttributes()))
            }
            output.append(renderedBlock(block))
        }
        return output
    }

    private static func renderedBlock(_ block: String) -> NSAttributedString {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: "", attributes: bodyAttributes())
        }

        if trimmed.hasPrefix("```"), trimmed.hasSuffix("```") {
            return renderedCodeBlock(trimmed)
        }

        let lines = trimmed.components(separatedBy: "\n")
        if lines.count > 1, lines.allSatisfy({ listMatch(in: $0) != nil }) {
            let output = NSMutableAttributedString()
            for (index, line) in lines.enumerated() {
                if index > 0 { output.append(NSAttributedString(string: "\n", attributes: bodyAttributes())) }
                if let renderedLine = renderedListLine(line) {
                    output.append(renderedLine)
                }
            }
            return output
        }

        if lines.count > 1, lines.allSatisfy({ quoteContent(in: $0) != nil }) {
            let output = NSMutableAttributedString()
            for (index, line) in lines.enumerated() {
                if index > 0 { output.append(NSAttributedString(string: "\n", attributes: bodyAttributes())) }
                output.append(renderedQuoteLine(line))
            }
            return output
        }

        if let renderedHeading = renderedHeadingLine(trimmed) {
            return renderedHeading
        }

        return renderedParagraph(trimmed)
    }

    private static func renderedHeadingLine(_ line: String) -> NSAttributedString? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        let match = nsLine.range(of: #"^(#{1,3})\s+(.+)$"#, options: .regularExpression, range: range)
        guard match.location != NSNotFound else { return nil }

        let hashesRange = nsLine.range(of: #"^(#{1,3})"#, options: .regularExpression, range: range)
        let hashes = nsLine.substring(with: hashesRange)
        let contentStart = hashesRange.location + hashesRange.length
        let content = nsLine.substring(from: min(nsLine.length, contentStart)).trimmingCharacters(in: .whitespaces)

        let fontSize: CGFloat
        switch hashes.count {
        case 1: fontSize = 18
        case 2: fontSize = 15
        default: fontSize = 13
        }
        return inlineAttributedString(
            from: content,
            baseAttributes: headingAttributes(fontSize: fontSize)
        )
    }

    private static func renderedParagraph(_ text: String) -> NSAttributedString {
        let joined = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        return inlineAttributedString(from: joined, baseAttributes: bodyAttributes())
    }

    private static func renderedCodeBlock(_ text: String) -> NSAttributedString {
        let stripped = text
            .replacingOccurrences(of: #"^```[A-Za-z0-9_-]*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```$"#, with: "", options: .regularExpression)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.headIndent = 6
        paragraphStyle.firstLineHeadIndent = 6
        return NSAttributedString(
            string: stripped,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.06),
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private static func renderedListLine(_ line: String) -> NSAttributedString? {
        guard let match = listMatch(in: line) else { return nil }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 18
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.lineSpacing = 2
        let prefixAttributes = bodyAttributes(paragraphStyle: paragraphStyle)
        let prefix = NSAttributedString(string: match.prefix, attributes: prefixAttributes)
        let content = inlineAttributedString(
            from: match.content,
            baseAttributes: bodyAttributes(paragraphStyle: paragraphStyle)
        )
        let output = NSMutableAttributedString(attributedString: prefix)
        output.append(content)
        return output
    }

    private static func renderedQuoteLine(_ line: String) -> NSAttributedString {
        let content = quoteContent(in: line) ?? line
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 12
        paragraphStyle.firstLineHeadIndent = 12
        paragraphStyle.lineSpacing = 2
        let output = NSMutableAttributedString(
            string: "▍ ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        output.append(
            inlineAttributedString(
                from: content,
                baseAttributes: italicizedAttributes(from: bodyAttributes(paragraphStyle: paragraphStyle))
            )
        )
        return output
    }

    private static func listMatch(in line: String) -> (prefix: String, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let nsLine = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        let numbered = nsLine.range(of: #"^(\d+)[.)]\s+(.+)$"#, options: .regularExpression, range: fullRange)
        if numbered.location != NSNotFound {
            let numberRange = nsLine.range(of: #"^\d+"#, options: .regularExpression, range: fullRange)
            let number = nsLine.substring(with: numberRange)
            let content = nsLine.substring(from: min(nsLine.length, numberRange.location + numberRange.length + 2))
            return ("\(number). ", content)
        }

        let bullet = nsLine.range(of: #"^([*•-])\s+(.+)$"#, options: .regularExpression, range: fullRange)
        if bullet.location != NSNotFound {
            let markerRange = nsLine.range(of: #"^[*•-]"#, options: .regularExpression, range: fullRange)
            let marker = nsLine.substring(with: markerRange)
            let content = nsLine.substring(from: min(nsLine.length, markerRange.location + markerRange.length + 1))
            let prefix = marker == "-" ? "— " : "• "
            return (prefix, content)
        }
        return nil
    }

    private static func quoteContent(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let nsLine = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        let match = nsLine.range(of: #"^>\s+(.+)$"#, options: .regularExpression, range: fullRange)
        guard match.location != NSNotFound else { return nil }
        return nsLine.substring(from: min(nsLine.length, 2)).trimmingCharacters(in: .whitespaces)
    }

    private static func inlineAttributedString(
        from text: String,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            if hasMarker("**", in: characters, at: index),
               let end = closingMarker("**", in: characters, from: index + 2) {
                let content = String(characters[(index + 2)..<end])
                output.append(
                    NSAttributedString(
                        string: content,
                        attributes: boldedAttributes(from: baseAttributes)
                    )
                )
                index = end + 2
                continue
            }

            if hasMarker("__", in: characters, at: index),
               let end = closingMarker("__", in: characters, from: index + 2) {
                let content = String(characters[(index + 2)..<end])
                output.append(
                    NSAttributedString(
                        string: content,
                        attributes: boldedAttributes(from: baseAttributes)
                    )
                )
                index = end + 2
                continue
            }

            if characters[index] == "`", let end = closingMarker("`", in: characters, from: index + 1) {
                let content = String(characters[(index + 1)..<end])
                output.append(
                    NSAttributedString(
                        string: content,
                        attributes: codeAttributes(from: baseAttributes)
                    )
                )
                index = end + 1
                continue
            }

            if characters[index] == "[",
               let closeBracket = firstIndex(of: "]", in: characters, from: index + 1),
               closeBracket + 1 < characters.count,
               characters[closeBracket + 1] == "(",
               let closeParen = firstIndex(of: ")", in: characters, from: closeBracket + 2) {
                let label = String(characters[(index + 1)..<closeBracket])
                output.append(
                    NSAttributedString(
                        string: label,
                        attributes: linkLikeAttributes(from: baseAttributes)
                    )
                )
                index = closeParen + 1
                continue
            }

            if characters[index] == "*",
               !hasMarker("**", in: characters, at: index),
               let end = closingMarker("*", in: characters, from: index + 1) {
                let content = String(characters[(index + 1)..<end])
                output.append(
                    NSAttributedString(
                        string: content,
                        attributes: italicizedAttributes(from: baseAttributes)
                    )
                )
                index = end + 1
                continue
            }

            if characters[index] == "_",
               !hasMarker("__", in: characters, at: index),
               let end = closingMarker("_", in: characters, from: index + 1) {
                let content = String(characters[(index + 1)..<end])
                output.append(
                    NSAttributedString(
                        string: content,
                        attributes: italicizedAttributes(from: baseAttributes)
                    )
                )
                index = end + 1
                continue
            }

            output.append(
                NSAttributedString(
                    string: String(characters[index]),
                    attributes: baseAttributes
                )
            )
            index += 1
        }

        return output
    }

    private static func hasMarker(_ marker: String, in characters: [Character], at index: Int) -> Bool {
        let markerChars = Array(marker)
        guard index + markerChars.count <= characters.count else { return false }
        return Array(characters[index..<(index + markerChars.count)]) == markerChars
    }

    private static func closingMarker(_ marker: String, in characters: [Character], from start: Int) -> Int? {
        let markerChars = Array(marker)
        guard !markerChars.isEmpty, start < characters.count else { return nil }
        var index = start
        while index + markerChars.count <= characters.count {
            if Array(characters[index..<(index + markerChars.count)]) == markerChars {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func firstIndex(of character: Character, in characters: [Character], from start: Int) -> Int? {
        guard start < characters.count else { return nil }
        for index in start..<characters.count where characters[index] == character {
            return index
        }
        return nil
    }

    private static func bodyAttributes(paragraphStyle: NSParagraphStyle? = nil) -> [NSAttributedString.Key: Any] {
        let style = paragraphStyle ?? defaultParagraphStyle()
        return [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ]
    }

    private static func headingAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static func codeAttributes(from base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = base
        let size = (attributes[.font] as? NSFont)?.pointSize ?? 12
        attributes[.font] = NSFont.monospacedSystemFont(ofSize: max(11, size - 0.5), weight: .regular)
        attributes[.backgroundColor] = NSColor.controlAccentColor.withAlphaComponent(0.08)
        return attributes
    }

    private static func boldedAttributes(from base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = base
        let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        if let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) as NSFont? {
            attributes[.font] = bold
        } else {
            attributes[.font] = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        }
        return attributes
    }

    private static func italicizedAttributes(from base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = base
        let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
        attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        return attributes
    }

    private static func linkLikeAttributes(from base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = base
        attributes[.foregroundColor] = NSColor.linkColor
        return attributes
    }

    private static func defaultParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        return style
    }

    private static func estimatedOutputRatePerMillionTokens(for model: String) -> Double {
        let lower = model.lowercased()
        if lower.contains("ollama") || lower.contains("local") { return 0 }
        if lower.contains("opus") { return 25.0 }
        if lower.contains("sonnet") { return 15.0 }
        if lower.contains("haiku") { return 5.0 }
        if lower.contains("gpt-5 pro") || lower.contains("gpt-5-pro") { return 120.0 }
        if lower.contains("codex-mini-latest") { return 6.0 }
        if lower.contains("codex-mini") || lower.contains("gpt-5 mini") || lower.contains("gpt-5-mini") { return 2.0 }
        if lower.contains("codex") || lower.contains("gpt-5") || lower.contains("gpt-4.1") || lower.contains("gpt-4o") {
            return 10.0
        }
        if lower.contains("grok") { return 15.0 }
        if lower.contains("deepseek") { return 0.42 }
        if lower.contains("minimax m2.5") || lower.contains("minimax-m2.5") { return 1.20 }
        if lower.contains("minimax") { return 1.10 }
        if lower.contains("gemini") { return 10.0 }
        return 1.0
    }

    static func formattedCost(_ value: Double) -> String {
        let positive = max(0, value)
        if positive >= 1 {
            return String(format: "$%.2f", positive)
        }
        if positive >= 0.01 {
            return String(format: "$%.3f", positive)
        }
        return String(format: "$%.4f", positive)
    }

    private var metricsLine: String {
        "\(metrics.words)w • ~\(metrics.tokens)t • \(Self.formattedCost(metrics.estimatedCost))"
    }

    private var pricingRows: [(label: String, cost: Double, isActive: Bool)] {
        [
            ("Current: \(activeModelLabel)", metrics.estimatedCost, true),
            ("Claude Sonnet 4.x", costForTokens(ratePerMillion: 15.0), false),
            ("Claude Opus 4.x", costForTokens(ratePerMillion: 25.0), false),
            ("GPT / Codex flagship", costForTokens(ratePerMillion: 10.0), false),
            ("GPT / Codex mini", costForTokens(ratePerMillion: 2.0), false),
            ("Grok", costForTokens(ratePerMillion: 15.0), false),
            ("DeepSeek", costForTokens(ratePerMillion: 0.42), false),
            ("MiniMax M2.5", costForTokens(ratePerMillion: 1.20), false),
            ("Local", 0, false)
        ]
    }

    private var activeModelLabel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown model" : trimmed
    }

    private var panelBackground: Color {
        settings.isDarkMode ? Color(white: 0.115) : Color(white: 0.985)
    }

    private var panelBorder: Color {
        settings.isDarkMode ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    private var metricsTextColor: Color {
        settings.isDarkMode ? .white.opacity(0.62) : .black.opacity(0.56)
    }

    private func costForTokens(ratePerMillion: Double) -> Double {
        (Double(metrics.tokens) * ratePerMillion) / 1_000_000.0
    }

    private func copyAllToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(renderedAnswer.string, forType: .string)
        if let rtf = try? renderedAnswer.data(
            from: NSRange(location: 0, length: renderedAnswer.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pasteboard.setData(rtf, forType: .rtf)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(summaryChip)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .overlay(
                        Capsule()
                            .stroke(.secondary.opacity(0.45), lineWidth: 1)
                    )
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Text(metricsLine)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(metricsTextColor)
                        .lineLimit(1)
                    Button {
                        showPricingPopover.toggle()
                    } label: {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(metricsTextColor.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showPricingPopover, arrowEdge: .top) {
                        PricingBreakdownPopover(
                            tokenCount: metrics.tokens,
                            rows: pricingRows,
                            isDarkMode: settings.isDarkMode
                        )
                    }
                }
            }

            SelectableAttributedTextView(
                attributedText: renderedAnswer,
                isDarkMode: settings.isDarkMode
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    copyAllToPasteboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.78))
                }
                .buttonStyle(.plain)
                .help("Copy all")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(panelBorder, lineWidth: 1)
                )
        )
        .background(PanelAppearanceSyncView(isDarkMode: settings.isDarkMode))
        .frame(
            minWidth: 220,
            idealWidth: contentSize.width,
            maxWidth: .infinity,
            minHeight: 120,
            idealHeight: contentSize.height,
            maxHeight: .infinity
        )
    }
}

private struct SelectableAttributedTextView: NSViewRepresentable {
    let attributedText: NSAttributedString
    let isDarkMode: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(attributedText)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
        scrollView.appearance = appearance
        textView.appearance = appearance
        if !textView.attributedString().isEqual(to: attributedText) {
            textView.textStorage?.setAttributedString(attributedText)
        }
    }
}

private struct PricingBreakdownPopover: View {
    let tokenCount: Int
    let rows: [(label: String, cost: Double, isActive: Bool)]
    let isDarkMode: Bool

    private var background: Color {
        isDarkMode ? Color(white: 0.13) : Color.white
    }

    private var border: Color {
        isDarkMode ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cost estimate for ~\(tokenCount) output tokens")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isDarkMode ? Color.white.opacity(0.9) : Color.black.opacity(0.82))

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .font(.system(size: 10.5, weight: row.isActive ? .semibold : .regular))
                        .foregroundStyle(row.isActive ? (isDarkMode ? Color.white.opacity(0.92) : Color.black.opacity(0.86)) : (isDarkMode ? Color.white.opacity(0.72) : Color.black.opacity(0.68)))
                    Spacer(minLength: 12)
                    Text(InlineCursorAnswerPopoverView.formattedCost(row.cost))
                        .font(.system(size: 10.5, weight: row.isActive ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(row.isActive ? (isDarkMode ? Color.white.opacity(0.92) : Color.black.opacity(0.86)) : (isDarkMode ? Color.white.opacity(0.72) : Color.black.opacity(0.68)))
                }
            }

            Text("Heuristic output-only estimate. Real billed usage depends on provider, model, prompt tokens, caching, and routing.")
                .font(.system(size: 9))
                .foregroundStyle(isDarkMode ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 250, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
        )
    }
}

private struct PanelAppearanceSyncView: NSViewRepresentable {
    let isDarkMode: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let appearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
        nsView.window?.appearance = appearance
        nsView.window?.backgroundColor = .clear
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
