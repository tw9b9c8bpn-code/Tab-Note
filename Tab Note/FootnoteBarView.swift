//
//  FootnoteBarView.swift
//  Tab Note
//
//  Created by Kien Tran on 2026-03-03.
//

import SwiftUI

// MARK: - FootnoteBarView

struct FootnoteBarView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var store: NotesStore
    let windowID: String
    @State private var showInfoPopover = false
    @State private var showSettings = false
    @State private var isAIProcessing = false
    @State private var showAIPromptPanel = false
    @State private var aiStatusText = ""
    @State private var showResponseModePopover = false
    @State private var showExpertModePopover = false
    @State private var showVoiceModePopover = false
    private let aiModeControlFrame: CGFloat = 15
    private let aiModeControlGlyph: CGFloat = 9

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Button(action: toggleAIPromptPanel) {
                        Group {
                            if isAIProcessing {
                                ProgressView()
                                    .scaleEffect(0.42)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 13, weight: .medium))
                            }
                        }
                        .foregroundColor(
                            settings.isDarkMode
                            ? .white.opacity(showAIPromptPanel ? 0.88 : 0.45)
                            : .black.opacity(showAIPromptPanel ? 0.82 : 0.42)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("AI prompt matrix (Cmd+Shift+I)")

                    if !aiStatusText.isEmpty {
                        Text(aiStatusText)
                            .font(.system(size: 7))
                            .foregroundColor(settings.isDarkMode ? .white.opacity(0.4) : .black.opacity(0.35))
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                .padding(.leading, 8)

                Spacer()

                HStack(spacing: 6) {
                    Button(action: { cycleFontForward() }) {
                        Text(fontLabel)
                            .font(fontPreviewFont)
                            .foregroundColor(settings.isDarkMode ? .white.opacity(0.6) : .black.opacity(0.5))
                            .frame(width: 18)
                            .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                    .help("Font: \(settings.selectedFontEnum.displayName)")

                    Button(action: { settings.isDarkMode.toggle() }) {
                        Image(systemName: settings.isDarkMode ? "moon.fill" : "sun.max.fill")
                            .font(.system(size: 9))
                            .foregroundColor(settings.isDarkMode ? .yellow.opacity(0.8) : .orange)
                    }
                    .buttonStyle(.plain)
                    .help(settings.isDarkMode ? "Light Mode" : "Dark Mode")

                    Button(action: { showInfoPopover.toggle() }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .foregroundColor(settings.isDarkMode ? .white.opacity(0.5) : .black.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showInfoPopover, arrowEdge: .top) { QuickGuideView() }

                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gear")
                            .font(.system(size: 9))
                            .foregroundColor(settings.isDarkMode ? .white.opacity(0.5) : .black.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showSettings) {
                        SettingsView().environmentObject(settings).environmentObject(store)
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(height: 21)
            .background(Color.clear)

            if showAIPromptPanel {
                aiPromptMatrixBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .inlineAIStatusDidChange)) { note in
            if let targetWindowID = note.object as? String, targetWindowID != windowID {
                return
            }
            let info = note.userInfo ?? [:]
            if let inFlight = info["inFlight"] as? Bool {
                isAIProcessing = inFlight
            }
            if let status = info["status"] as? String {
                withAnimation {
                    aiStatusText = status
                }
            }
            if let inFlight = info["inFlight"] as? Bool, !inFlight {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if !self.isAIProcessing {
                        withAnimation {
                            self.aiStatusText = ""
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAIPanel)) { note in
            if let targetWindowID = note.object as? String, targetWindowID != windowID {
                return
            }
            toggleAIPromptPanel()
        }
    }

    // MARK: - Font helpers

    private var fontLabel: String {
        switch settings.selectedFontEnum {
        case .sansSerif: return "Aa"
        case .serif: return "Ag"
        case .monospace: return "A_"
        }
    }

    private var fontPreviewFont: Font {
        switch settings.selectedFontEnum {
        case .sansSerif: return .system(size: 9, weight: .medium)
        case .serif: return .custom("Georgia", size: 9)
        case .monospace: return .system(size: 9, weight: .medium, design: .monospaced)
        }
    }

    private func cycleFontForward() {
        switch settings.selectedFontEnum {
        case .sansSerif: settings.selectedFontEnum = .serif
        case .serif: settings.selectedFontEnum = .monospace
        case .monospace: settings.selectedFontEnum = .sansSerif
        }
    }

    // MARK: - AI

    private var promptConfig: PromptInjectionConfiguration {
        settings.promptInjectionConfiguration
    }

    private var aiPromptMatrixBar: some View {
        HStack(spacing: 2) {
            lengthPresetQuickPicker
            Spacer().frame(width: 10)
            responseModeMenu
            expertModeMenu
            voiceModeMenu
            Spacer(minLength: 0)
            clearAIPromptButton
        }
        .padding(.horizontal, 4)
        .frame(height: 21)
        .background(settings.isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.035))
    }

    private var lengthPresetQuickPicker: some View {
        HStack(spacing: 1) {
            ForEach(promptConfig.responseLengthOptions, id: \.id) { option in
                Button {
                    settings.aiResponseLengthID = option.id
                } label: {
                    lengthQuickPickLabel(option)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func lengthQuickPickLabel(_ option: PromptInjectionOption) -> some View {
        let isSelected = settings.aiResponseLengthID == option.id
        let activeText = settings.isDarkMode ? Color.white.opacity(0.95) : Color.black.opacity(0.95)
        let inactiveText = settings.isDarkMode ? Color.white.opacity(0.32) : Color.black.opacity(0.32)
        let stroke = settings.isDarkMode ? Color.white : Color.black
        return Text(option.label)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(isSelected ? activeText : inactiveText)
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .stroke(stroke, lineWidth: isSelected ? 0.85 : 0)
            )
            .contentShape(Circle())
            .help("Response length: \(option.helper ?? option.label)")
    }

    private var responseModeMenu: some View {
        Button(action: toggleResponseModePopover) {
            matrixMenuIcon(
                symbol: "list.bullet.rectangle.portrait",
                isActive: settings.aiResponseModeID != nil
            )
        }
        .buttonStyle(.plain)
        .help("Response mode: \(promptConfig.responseModeMenuLabel(for: settings.aiResponseModeID))")
        .popover(isPresented: $showResponseModePopover, arrowEdge: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        settings.aiResponseModeID = nil
                        showResponseModePopover = false
                    } label: {
                        selectorRow(
                            title: "None",
                            isSelected: settings.aiResponseModeID == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(promptConfig.responseModeOptions, id: \.id) { option in
                        Button {
                            settings.aiResponseModeID = option.id
                            showResponseModePopover = false
                        } label: {
                            selectorRow(
                                title: promptConfig.responseModeMenuLabel(for: option.id),
                                isSelected: settings.aiResponseModeID == option.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(width: 220, height: 190)
        }
    }

    private var expertModeMenu: some View {
        Button(action: toggleExpertModePopover) {
            matrixMenuIcon(
                symbol: "graduationcap",
                isActive: settings.aiExpertModeID != nil
            )
        }
        .buttonStyle(.plain)
        .help("Expert mode: \(promptConfig.expertModeMenuLabel(for: settings.aiExpertModeID))")
        .popover(isPresented: $showExpertModePopover, arrowEdge: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        settings.aiExpertModeID = nil
                        showExpertModePopover = false
                    } label: {
                        selectorRow(
                            title: "None",
                            isSelected: settings.aiExpertModeID == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(promptConfig.expertModeOptions, id: \.id) { option in
                        Button {
                            settings.aiExpertModeID = option.id
                            showExpertModePopover = false
                        } label: {
                            selectorRow(
                                title: promptConfig.expertModeMenuLabel(for: option.id),
                                isSelected: settings.aiExpertModeID == option.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(width: 230, height: 240)
        }
    }

    private var voiceModeMenu: some View {
        Button(action: toggleVoiceModePopover) {
            matrixMenuIcon(
                symbol: "quote.bubble",
                isActive: settings.aiVoiceModeID != nil
            )
        }
        .buttonStyle(.plain)
        .help("Voice mode: \(promptConfig.voiceModeMenuLabel(for: settings.aiVoiceModeID))")
        .popover(isPresented: $showVoiceModePopover, arrowEdge: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        settings.aiVoiceModeID = nil
                        showVoiceModePopover = false
                    } label: {
                        selectorRow(
                            title: "None",
                            isSelected: settings.aiVoiceModeID == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(promptConfig.voiceModeOptions, id: \.id) { option in
                        Button {
                            settings.aiVoiceModeID = option.id
                            showVoiceModePopover = false
                        } label: {
                            selectorRow(
                                title: promptConfig.voiceModeMenuLabel(for: option.id),
                                isSelected: settings.aiVoiceModeID == option.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(width: 230, height: 240)
        }
    }

    private func selectorRow(title: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .semibold))
                .opacity(isSelected ? 1 : 0)
            Text(title)
                .font(.system(size: 10))
            Spacer(minLength: 0)
        }
        .foregroundColor(.primary.opacity(isSelected ? 0.95 : 0.7))
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }

    private func matrixMenuIcon(symbol: String, isActive: Bool) -> some View {
        let opacity = isActive ? 0.82 : 0.14
        return Image(systemName: symbol)
            .font(.system(size: aiModeControlGlyph, weight: .medium))
            .foregroundColor(settings.isDarkMode ? .white.opacity(opacity) : .black.opacity(opacity))
            .frame(width: aiModeControlFrame, height: aiModeControlFrame)
    }

    private var clearAIPromptButton: some View {
        Button(action: clearAIPromptSelections) {
            Image(systemName: "trash")
                .font(.system(size: aiModeControlGlyph, weight: .medium))
                .foregroundColor(settings.isDarkMode ? .white.opacity(0.28) : .black.opacity(0.22))
                .frame(width: aiModeControlFrame, height: aiModeControlFrame)
        }
        .buttonStyle(.plain)
        .help("Clear AI prompt selections")
    }

    private func clearAIPromptSelections() {
        settings.resetAIPromptSelection()
    }

    private func toggleResponseModePopover() {
        let next = !showResponseModePopover
        showResponseModePopover = next
        if next {
            showExpertModePopover = false
            showVoiceModePopover = false
        }
    }

    private func toggleExpertModePopover() {
        let next = !showExpertModePopover
        showExpertModePopover = next
        if next {
            showResponseModePopover = false
            showVoiceModePopover = false
        }
    }

    private func toggleVoiceModePopover() {
        let next = !showVoiceModePopover
        showVoiceModePopover = next
        if next {
            showResponseModePopover = false
            showExpertModePopover = false
        }
    }

    private func toggleAIPromptPanel() {
        withAnimation(.easeOut(duration: 0.16)) {
            showAIPromptPanel.toggle()
        }
    }
}

// MARK: - AI Popup View

struct AIPopupView: View {
    let result: AIResult
    let isDarkMode: Bool
    var showBackground: Bool = true
    let onClose: () -> Void

    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.purple.opacity(0.8))
                Text(result.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isDarkMode ? .white.opacity(0.9) : .black.opacity(0.8))
                Spacer()
                // Copy button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.content, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
                }) {
                    Text(isCopied ? "Copied!" : "Copy")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isDarkMode ? .white.opacity(0.5) : .black.opacity(0.45))
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isDarkMode ? .white.opacity(0.4) : .black.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider().opacity(0.3)

            // Scrollable content
            ScrollView {
                Text(result.content)
                    .font(.system(size: 11))
                    .foregroundColor(isDarkMode ? .white.opacity(0.85) : .black.opacity(0.75))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxHeight: 220)
        }
        .if(showBackground) { v in
            v.background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDarkMode ? Color(white: 0.18) : Color(white: 0.97))
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(width: 320)
    }
}

// MARK: - Quick Guide

struct QuickGuideView: View {
    @EnvironmentObject var settings: SettingsManager

    private var hotkeyLabel: String {
        settings.hotkeyDisplayLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tab Note — Quick Guide")
                .font(.system(size: 14, weight: .bold))
            Divider()
            Group {
                shortcutRow(hotkeyLabel,   "Show / Hide Tab Note")
                shortcutRow("⌘T",          "New Note")
                shortcutRow("⌘Space",      "Delete Note / Close Tab")
                shortcutRow("⌘⇧T",         "Recover Deleted Tab")
                shortcutRow("⌘1–9",        "Switch to Tab 1–9")
                shortcutRow("⌘⌥← / →",    "Move Tab Left / Right")
                shortcutRow("⌘⇧⌥← / →",    "Switch Tab Left / Right")
                shortcutRow("⌘L",          "Rename current tab")
                shortcutRow("⌘B / ⌘I",    "Bold / Italic")
                shortcutRow("⌘U",          "Highlight text")
                shortcutRow("⌘F",          "Toggle Search bar")
                shortcutRow("⌘⇧H",         "Toggle Tab Area (Focus Mode)")
                shortcutRow("⌘⇧I",         "Toggle AI prompt matrix")
                shortcutRow("???",         "Answer current paragraph with AI")
                shortcutRow("? + ⇥",       "Answer current paragraph with AI")
            }
            Divider()
            Group {
                Text("• Right-click tab to pin / rename / export / delete")
                    .font(.system(size: 12))
                Text("• Right-click text for styles & theme palette")
                    .font(.system(size: 12))
                Text("• Deleted notes auto-purge after 30 days")
                    .font(.system(size: 12))
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("About")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text("Created by")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Link("Kien Tran", destination: URL(string: "https://kientran.ca")!)
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack {
            Text(shortcut)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 80, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
        }
    }
}
