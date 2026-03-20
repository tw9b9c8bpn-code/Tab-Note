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
    let windowID: String
    @State private var showInfoPopover = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 10)

            HStack(spacing: 2) {
                FootnoteButton(
                    isDarkMode: settings.isDarkMode,
                    helpText: "Font: \(settings.selectedFontEnum.displayName)",
                    action: cycleFontForward
                ) {
                    Text(fontLabel)
                        .font(fontPreviewFont)
                }

                FootnoteButton(
                    isDarkMode: settings.isDarkMode,
                    helpText: settings.isDarkMode ? "Light Mode" : "Dark Mode",
                    action: { settings.isDarkMode.toggle() }
                ) {
                    Image(systemName: settings.isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(settings.isDarkMode ? Color.yellow.opacity(0.8) : Color.orange)
                }

                FootnoteButton(
                    isDarkMode: settings.isDarkMode,
                    helpText: "Quick guide",
                    action: { showInfoPopover.toggle() }
                ) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                }
                .popover(isPresented: $showInfoPopover, arrowEdge: .top) { QuickGuideView() }

                FootnoteButton(
                    isDarkMode: settings.isDarkMode,
                    helpText: "Settings",
                    action: openSettings
                ) {
                    Image(systemName: "gear")
                        .font(.system(size: 9))
                }
            }
            .padding(.trailing, 6)
        }
        .frame(height: 21)
        .background(Color.clear)
    }

    // MARK: - Font

    private var fontLabel: String {
        switch settings.selectedFontEnum {
        case .sansSerif: return "Aa"
        case .serif:     return "Ag"
        case .monospace: return "A_"
        }
    }

    private var fontPreviewFont: Font {
        switch settings.selectedFontEnum {
        case .sansSerif: return .system(size: 9, weight: .medium)
        case .serif:     return .custom("Georgia", size: 9)
        case .monospace: return .system(size: 9, weight: .medium, design: .monospaced)
        }
    }

    private func cycleFontForward() {
        switch settings.selectedFontEnum {
        case .sansSerif: settings.selectedFontEnum = .serif
        case .serif:     settings.selectedFontEnum = .monospace
        case .monospace: settings.selectedFontEnum = .sansSerif
        }
    }

    private func openSettings() {
        AppDelegate.shared?.showFloatingSettings()
    }
}

// MARK: - Footnote Button

private struct FootnoteButton<Label: View>: View {
    let isDarkMode: Bool
    let helpText: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(
                    isDarkMode
                        ? Color.white.opacity(isHovering ? 0.82 : 0.5)
                        : Color.black.opacity(isHovering ? 0.72 : 0.4)
                )
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            isHovering
                                ? (isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                                : Color.clear
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tab Note — Quick Guide")
                .font(.system(size: 14, weight: .bold))
            Divider()
            Group {
                shortcutRow(settings.hotkeyDisplayLabel, "Show / Hide Tab Note")
                shortcutRow("⌘T",          "New Note")
                shortcutRow("⌘Space",      "Delete Note / Close Tab")
                shortcutRow("⌘⇧T",         "Recover Deleted Tab")
                shortcutRow("⌘1–9",        "Switch to Tab 1–9")
                shortcutRow("⌘⌥← / →",    "Move Tab Left / Right")
                shortcutRow("⌘⇧⌥← / →",   "Switch Tab Left / Right")
                shortcutRow("⌘L",          "Rename current tab")
                shortcutRow("⌘B / ⌘I",    "Bold / Italic")
                shortcutRow("⌘U",          "Highlight text")
                shortcutRow("⌘F",          "Toggle Search bar")
                shortcutRow("⌘⇧H",         "Toggle Tab Area (Focus Mode)")
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
            HStack(spacing: 4) {
                Text("Created by")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Link("Kien Tran", destination: URL(string: "https://kientran.ca")!)
                    .font(.system(size: 11, weight: .medium))
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
