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
    var onAIResult: (AIResult) -> Void = { _ in }
    var lastAIResult: AIResult? = nil
    @State private var showInfoPopover = false
    @State private var showSettings = false
    @State private var isAIProcessing = false
    @State private var aiStatusText = ""
    @State private var showResultPopover = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: AI menu button + reopen button + status text
            HStack(spacing: 4) {
                // AI ▼ — left click opens menu
                Menu {
                    Button {
                        triggerAI(action: .addContent)
                    } label: {
                        Label("Add Content", systemImage: "plus.bubble")
                    }
                    Divider()
                    Button {
                        triggerAI(action: .improvePrompt)
                    } label: {
                        Label("Improve Prompt", systemImage: "pencil.and.outline")
                    }
                    Button {
                        triggerAI(action: .addSuggestions)
                    } label: {
                        Label("Add Suggestions", systemImage: "lightbulb")
                    }
                } label: {
                    HStack(spacing: 2) {
                        if isAIProcessing {
                            ProgressView().scaleEffect(0.3).frame(width: 8, height: 8)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 7))
                        }
                        Text("AI").font(.system(size: 7, weight: .medium))
                    }
                    .foregroundColor(settings.isDarkMode ? .white.opacity(0.7) : .black.opacity(0.6))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3)
                        .fill(settings.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isAIProcessing)

                // Reopen last result button — only visible when a result exists
                if lastAIResult != nil {
                    Button(action: { showResultPopover.toggle() }) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 9))
                            .foregroundColor(settings.isDarkMode ? .white.opacity(0.5) : .black.opacity(0.45))
                            .padding(3)
                            .background(RoundedRectangle(cornerRadius: 3)
                                .fill(settings.isDarkMode ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help("Reopen last AI result")
                    .popover(isPresented: $showResultPopover, arrowEdge: .top) {
                        if let r = lastAIResult {
                            AIPopupView(result: r, isDarkMode: settings.isDarkMode,
                                        showBackground: false) {
                                showResultPopover = false
                            }
                            .frame(width: 300)
                            .padding(4)
                        }
                    }
                }

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

            // Right: Font, Dark/Light, Info, Settings
            HStack(spacing: 6) {

                    Button(action: { cycleFontForward() }) {
                        Text(fontLabel)
                            .font(fontPreviewFont)
                            .foregroundColor(settings.isDarkMode ? .white.opacity(0.6) : .black.opacity(0.5))
                            .frame(width: 18).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3)
                                .fill(settings.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
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

    private func triggerAI(action: AIAction) {
        guard !isAIProcessing else { return }
        guard let activeNote = store.selectedNote(in: windowID) else {
            aiStatusText = "No active note"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { aiStatusText = "" }
            return
        }

        isAIProcessing = true
        let capturedContent = activeNote.content

        let actionLabel: String
        switch action {
        case .addContent:    actionLabel = "Generating..."
        case .improvePrompt: actionLabel = "Improving prompt..."
        case .addSuggestions: actionLabel = "Adding suggestions..."
        }
        withAnimation { aiStatusText = actionLabel }

        AIService.shared.generateContent(
            action: action,
            noteContent: capturedContent,
            settings: settings,
            onStatus: { status in
                DispatchQueue.main.async {
                    withAnimation { self.aiStatusText = status }
                }
            },
            completion: { result in
                DispatchQueue.main.async {
                    self.isAIProcessing = false
                    switch result {
                    case .success(let newContent):
                        let popupTitle: String
                        switch action {
                        case .addContent:    popupTitle = "AI Generated Content"
                        case .improvePrompt: popupTitle = "AI Improved Prompt"
                        case .addSuggestions: popupTitle = "AI Suggestions"
                        }
                        // Fire callback → ContentView shows the popup
                        self.onAIResult(AIResult(title: popupTitle, content: newContent))
                        withAnimation { self.aiStatusText = "Done ✅" }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { self.aiStatusText = "" }
                        }

                    case .failure(let error):
                        withAnimation { self.aiStatusText = "Error: \(error.localizedDescription)" }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            withAnimation { self.aiStatusText = "" }
                        }
                    }
                }
            }
        )
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
                shortcutRow("⌘L",          "Rename current tab")
                shortcutRow("⌘B / ⌘I",    "Bold / Italic")
                shortcutRow("⌘U",          "Highlight text")
                shortcutRow("⌘F",          "Toggle Search bar")
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
