//
//  SettingsView.swift
//  Tab Note
//
//  Created by Kien Tran on 2026-03-03.
//

import AppKit
import SwiftUI

// MARK: - Design Tokens

private enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 40
}

private enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 18
}

// MARK: - Section Model

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case behavior = "Behavior"
    case data = "Data"
    case about = "About"

    var id: String { rawValue }

    /// Sections shown in the main nav list (About is pinned to the bottom separately)
    static var navCases: [SettingsSection] { [.general, .appearance, .behavior, .data] }

    var icon: String {
        switch self {
        case .general:    return "gear"
        case .appearance: return "paintbrush"
        case .behavior:   return "slider.horizontal.3"
        case .data:       return "internaldrive"
        case .about:      return "info.circle"
        }
    }

    var intro: String {
        switch self {
        case .general:    return "Configure your global shortcut and startup preferences."
        case .appearance: return "Customize how Tab Note looks and feels."
        case .behavior:   return "Control window placement and layout density."
        case .data:       return "Recover or permanently remove deleted notes."
        case .about:      return "App information and update preferences."
        }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let accentColor: Color
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let isDarkMode: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? accentColor : secondaryTextColor)
                    .frame(width: 18, alignment: .center)

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? primaryTextColor : secondaryTextColor)

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isDarkMode ? accentColor.opacity(0.16) : accentColor.opacity(0.10))
        } else if isHovering {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        }
    }
}

// MARK: - Main View

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var store: NotesStore
    @Environment(\.dismiss) private var dismiss

    let onClose: (() -> Void)?

    @State private var selectedSection: SettingsSection = .general

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            panelBackground

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 172)

                Rectangle()
                    .fill(dividerColor)
                    .frame(width: 1)

                detailPanel
            }

            CloseButton(isDarkMode: settings.isDarkMode, action: closeSettings)
                .padding(.top, Spacing.sm)
                .padding(.trailing, Spacing.sm)
        }
        .frame(minWidth: 580, minHeight: 460)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(primaryTextColor)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(SettingsSection.navCases) { section in
                    SidebarRow(
                        section: section,
                        isSelected: selectedSection == section,
                        accentColor: accentColor,
                        primaryTextColor: primaryTextColor,
                        secondaryTextColor: secondaryTextColor,
                        isDarkMode: settings.isDarkMode
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedSection = section
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)

            Spacer()

            Divider()
                .opacity(settings.isDarkMode ? 0.12 : 0.10)
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                SidebarRow(
                    section: .about,
                    isSelected: selectedSection == .about,
                    accentColor: accentColor,
                    primaryTextColor: primaryTextColor,
                    secondaryTextColor: secondaryTextColor,
                    isDarkMode: settings.isDarkMode
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedSection = .about
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.bottom, Spacing.xs)
        }
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                pageHeader
                sectionContent
            }
            .padding(Spacing.md)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(selectedSection.rawValue)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(primaryTextColor)

            Text(selectedSection.intro)
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general:    generalSection
        case .appearance: appearanceSection
        case .behavior:   behaviorSection
        case .data:       dataSection
        case .about:      aboutSection
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(spacing: Spacing.xs) {
            settingsCard {
                sectionHeader(
                    "Global Hotkey",
                    subtitle: "Choose the shortcut that reveals or hides Tab Note from anywhere."
                )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    fieldLabel("Modifiers")
                    HStack(spacing: Spacing.xs) {
                        modifierPill(label: "⌘ Cmd", flag: 0x0100)
                        modifierPill(label: "⇧ Shift", flag: 0x0200)
                        modifierPill(label: "⌥ Option", flag: 0x0800)
                        modifierPill(label: "⌃ Ctrl", flag: 0x1000)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    fieldLabel("Key")
                    HStack(spacing: Spacing.xs) {
                        Menu {
                            ForEach(hotkeyKeys, id: \.0) { code, label in
                                Button(label) { settings.hotkeyKeyCode = code }
                            }
                        } label: {
                            fieldMenuLabel("Key: \(SettingsManager.hotkeyKeyNames[settings.hotkeyKeyCode] ?? "?")")
                        }
                        .menuStyle(.borderlessButton)

                        Text("Current: \(settings.hotkeyDisplayLabel)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }

            settingsCard {
                sectionHeader("Startup", subtitle: "Control how Tab Note behaves when you log in.")

                toggleRow(
                    title: "Launch at Login",
                    subtitle: "Automatically start Tab Note when you log in.",
                    isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 })
                )
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(spacing: Spacing.xs) {
            settingsCard {
                sectionHeader("Color Mode", subtitle: "Switch between dark and light interface styles.")

                choiceGroup(
                    title: "Interface",
                    subtitle: nil,
                    selection: Binding(get: { settings.isDarkMode }, set: { settings.isDarkMode = $0 }),
                    options: [("Light", false), ("Dark", true)]
                )
            }

            settingsCard {
                sectionHeader("Typography", subtitle: "Choose the font family used in the note editor.")

                choiceGroup(
                    title: "Editor Font",
                    subtitle: nil,
                    selection: Binding(get: { settings.selectedFontEnum }, set: { settings.selectedFontEnum = $0 }),
                    options: FontChoice.allCases.map { ($0.displayName, $0) }
                )
            }

            settingsCard {
                sectionHeader("Tabs", subtitle: "Adjust the size and density of tab items.")

                stepperRow(
                    title: "Font Size",
                    subtitle: "Size of text inside each tab pill.",
                    value: Binding(get: { settings.tabFontSize }, set: { settings.tabFontSize = $0 }),
                    range: 8...14,
                    step: 1,
                    format: "%.0fpt"
                )

                stepperRow(
                    title: "Horizontal Padding",
                    subtitle: "Space on each side of tab label text.",
                    value: Binding(get: { settings.tabHPadding }, set: { settings.tabHPadding = $0 }),
                    range: 4...16,
                    step: 2,
                    format: "%.0fpx"
                )
            }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        VStack(spacing: Spacing.xs) {
            settingsCard {
                sectionHeader("Window Position", subtitle: "Choose where Tab Note appears when you invoke it.")

                choiceGroup(
                    title: "Show Window",
                    subtitle: "Applies to the main window and any detached windows.",
                    selection: Binding(get: { settings.positionModeEnum }, set: { settings.positionModeEnum = $0 }),
                    options: PositionMode.allCases.map { ($0.displayName, $0) }
                )
            }

            settingsCard {
                sectionHeader("Layout", subtitle: "Adjust tab bar density and window stacking behavior.")

                choiceGroup(
                    title: "Max Tab Rows",
                    subtitle: "Keep the tab bar compact before spilling into more rows.",
                    selection: Binding(get: { settings.maxTabRows }, set: { settings.maxTabRows = $0 }),
                    options: [("2", 2), ("3", 3), ("4", 4)]
                )

                toggleRow(
                    title: "Always on Top",
                    subtitle: "Keep the Tab Note window above other applications.",
                    isOn: Binding(get: { settings.alwaysOnTop }, set: { settings.alwaysOnTop = $0 })
                )
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(spacing: Spacing.xs) {
            settingsCard {
                sectionHeader(
                    "Deleted Notes",
                    subtitle: "Recovered notes return to your library. Notes are permanently removed after 30 days."
                )

                if store.deletedNotes.isEmpty {
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(secondaryTextColor)

                        Text("No deleted notes")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(primaryTextColor)

                        Text("Anything you delete will show up here until its recovery window expires.")
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryTextColor)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                } else {
                    LazyVStack(spacing: Spacing.xs) {
                        ForEach(store.deletedNotes) { note in
                            HStack(spacing: Spacing.sm) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(note.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(primaryTextColor)

                                    Text("Deleted \(note.deletedAt, style: .relative) ago")
                                        .font(.system(size: 11))
                                        .foregroundStyle(secondaryTextColor)
                                }

                                Spacer()

                                Button("Recover") { store.recoverNote(note) }
                                    .buttonStyle(SettingsPillButtonStyle(
                                        isDarkMode: settings.isDarkMode,
                                        tone: .accent,
                                        isSelected: false
                                    ))
                            }
                            .padding(Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .fill(fieldFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                    .stroke(outlineColor, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: Spacing.xs) {
            settingsCard {
                HStack(spacing: Spacing.md) {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Text("TN")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(accentColor)
                        )

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Tab Note")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(primaryTextColor)

                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryTextColor)

                        HStack(spacing: Spacing.xxs) {
                            Text("Created by")
                                .font(.system(size: 12))
                                .foregroundStyle(secondaryTextColor)
                            Link("Kien Tran", destination: URL(string: "https://kientran.ca")!)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(accentColor)
                        }
                    }

                    Spacer()
                }
            }

            settingsCard {
                sectionHeader("Updates", subtitle: "Check for new versions from the Sparkle feed.")

                HStack {
                    Button("Check for Updates") { AppUpdater.shared.checkForUpdates() }
                        .buttonStyle(SettingsPillButtonStyle(isDarkMode: settings.isDarkMode, tone: .accent, isSelected: false))
                    Spacer()
                }

                toggleRow(
                    title: "Auto-check on Launch",
                    subtitle: "Run an update check a few seconds after the app opens.",
                    isOn: Binding(get: { settings.autoCheckUpdates }, set: { settings.autoCheckUpdates = $0 })
                )
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Colors

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(
                LinearGradient(
                    colors: settings.isDarkMode
                    ? [
                        Color(red: 0.14, green: 0.14, blue: 0.16),
                        Color(red: 0.10, green: 0.10, blue: 0.12)
                    ]
                    : [
                        Color(red: 0.97, green: 0.96, blue: 0.93),
                        Color(red: 0.93, green: 0.93, blue: 0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 24, x: 0, y: 10)
    }

    private var primaryTextColor: Color {
        settings.isDarkMode ? .white.opacity(0.95) : .black.opacity(0.84)
    }

    private var secondaryTextColor: Color {
        settings.isDarkMode ? .white.opacity(0.62) : .black.opacity(0.55)
    }

    private var borderColor: Color {
        settings.isDarkMode ? .white.opacity(0.08) : .white.opacity(0.55)
    }

    private var cardFill: Color {
        settings.isDarkMode ? .white.opacity(0.05) : .white.opacity(0.72)
    }

    private var fieldFill: Color {
        settings.isDarkMode ? .white.opacity(0.05) : .white.opacity(0.82)
    }

    private var outlineColor: Color {
        settings.isDarkMode ? .white.opacity(0.09) : .black.opacity(0.08)
    }

    private var shadowColor: Color {
        settings.isDarkMode ? .black.opacity(0.35) : .black.opacity(0.12)
    }

    private var dividerColor: Color {
        settings.isDarkMode ? .white.opacity(0.07) : .black.opacity(0.06)
    }

    private var accentColor: Color {
        settings.isDarkMode
            ? Color(red: 0.89, green: 0.49, blue: 0.18)
            : Color(red: 0.90, green: 0.50, blue: 0.16)
    }

    // MARK: - Reusable Components

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            content()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(secondaryTextColor)
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        ToggleRow(
            title: title,
            subtitle: subtitle,
            isOn: isOn,
            isDarkMode: settings.isDarkMode,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor
        )
    }

    private func stepperRow(
        title: String,
        subtitle: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        format: String
    ) -> some View {
        StepperRow(
            title: title,
            subtitle: subtitle,
            value: value,
            range: range,
            step: step,
            format: format,
            isDarkMode: settings.isDarkMode,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor
        )
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(primaryTextColor)
    }

    private func modifierPill(label: String, flag: Int) -> some View {
        let isSelected = (settings.hotkeyModifiers & flag) != 0
        return Button(label) {
            if isSelected {
                settings.hotkeyModifiers &= ~flag
            } else {
                settings.hotkeyModifiers |= flag
            }
        }
        .buttonStyle(SettingsPillButtonStyle(isDarkMode: settings.isDarkMode, tone: .accent, isSelected: isSelected))
    }

    private func choiceGroup<Value: Hashable>(
        title: String,
        subtitle: String?,
        selection: Binding<Value>,
        options: [(String, Value)]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs - 1) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryTextColor)
            }

            HStack(spacing: Spacing.xs) {
                ForEach(0..<options.count, id: \.self) { index in
                    let option = options[index]
                    Button(option.0) {
                        selection.wrappedValue = option.1
                    }
                    .buttonStyle(SettingsPillButtonStyle(
                        isDarkMode: settings.isDarkMode,
                        tone: .accent,
                        isSelected: selection.wrappedValue == option.1
                    ))
                }
            }
        }
    }

    private func fieldMenuLabel(_ title: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(title).lineLimit(1)
            Spacer(minLength: Spacing.xxs)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(primaryTextColor.opacity(0.96))
        .padding(.horizontal, Spacing.sm - 2)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                .fill(settings.isDarkMode ? .white.opacity(0.08) : .white.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                .stroke(outlineColor.opacity(1.15), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func closeSettings() {
        if let onClose { onClose() } else { dismiss() }
    }

    private let hotkeyKeys: [(Int, String)] = SettingsManager.hotkeyKeyNames
        .map { ($0.key, $0.value) }
        .sorted { $0.1 < $1.1 }
}

// MARK: - Toggle Row

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>
    let isDarkMode: Bool
    let primaryTextColor: Color
    let secondaryTextColor: Color

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(primaryTextColor)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering
                    ? (isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Stepper Row

private struct StepperRow: View {
    let title: String
    let subtitle: String
    let value: Binding<CGFloat>
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let format: String
    let isDarkMode: Bool
    let primaryTextColor: Color
    let secondaryTextColor: Color

    @State private var isHovering = false

    private var accentColor: Color {
        isDarkMode
            ? Color(red: 0.89, green: 0.49, blue: 0.18)
            : Color(red: 0.90, green: 0.50, blue: 0.16)
    }

    private var btnFill: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.84)
    }
    private var btnStroke: Color {
        isDarkMode ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            HStack(spacing: 0) {
                StepperButton(label: "−", isDarkMode: isDarkMode) {
                    if value.wrappedValue - step >= range.lowerBound {
                        value.wrappedValue -= step
                    }
                }

                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(primaryTextColor)
                    .frame(minWidth: 36)
                    .multilineTextAlignment(.center)

                StepperButton(label: "+", isDarkMode: isDarkMode) {
                    if value.wrappedValue + step <= range.upperBound {
                        value.wrappedValue += step
                    }
                }
            }
            .background(
                Capsule().fill(isDarkMode ? Color.white.opacity(0.05) : Color.white.opacity(0.72))
            )
            .overlay(Capsule().stroke(btnStroke, lineWidth: 1))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering
                    ? (isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct StepperButton: View {
    let label: String
    let isDarkMode: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    isHovering
                        ? (isDarkMode ? Color.white.opacity(0.9) : Color.black.opacity(0.78))
                        : (isDarkMode ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                )
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovering)
    }
}

// MARK: - Close Button

private struct CloseButton: View {
    let isDarkMode: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var iconColor: Color {
        isDarkMode ? Color.white.opacity(isHovering ? 0.82 : 0.5) : Color.black.opacity(isHovering ? 0.72 : 0.4)
    }

    private var bgColor: Color {
        if isHovering {
            return isDarkMode ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
        } else {
            return isDarkMode ? Color.white.opacity(0.05) : Color.white.opacity(0.82)
        }
    }

    private var strokeColor: Color {
        isDarkMode ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(bgColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Close Settings")
    }
}

// MARK: - Pill Button Style

private struct SettingsPillButtonStyle: ButtonStyle {
    enum Tone { case neutral, accent, destructive }

    let isDarkMode: Bool
    let tone: Tone
    let isSelected: Bool
    var compact: Bool = false
    var minimumHeight: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        PillBody(
            configuration: configuration,
            isDarkMode: isDarkMode,
            tone: tone,
            isSelected: isSelected,
            compact: compact,
            minimumHeight: minimumHeight
        )
    }
}

private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let isDarkMode: Bool
    let tone: SettingsPillButtonStyle.Tone
    let isSelected: Bool
    let compact: Bool
    let minimumHeight: CGFloat?

    @State private var isHovering = false

    private var accentFill: Color {
        isDarkMode ? Color(red: 0.89, green: 0.49, blue: 0.18) : Color(red: 0.90, green: 0.50, blue: 0.16)
    }
    private var neutralFill: Color {
        isDarkMode ? .white.opacity(isHovering ? 0.10 : 0.06) : .white.opacity(isHovering ? 0.95 : 0.84)
    }
    private var destructiveFill: Color {
        isDarkMode ? Color.red.opacity(0.18) : Color.red.opacity(0.10)
    }
    private var activeStroke: Color {
        isDarkMode ? .white.opacity(0.10) : .black.opacity(0.08)
    }

    private var backgroundColor: Color {
        let base: Color
        switch tone {
        case .neutral:
            base = neutralFill
        case .accent:
            if isSelected {
                base = accentFill.opacity(isHovering ? 0.85 : 1)
            } else {
                base = isDarkMode
                    ? .white.opacity(isHovering ? 0.10 : 0.06)
                    : .white.opacity(isHovering ? 0.95 : 0.84)
            }
        case .destructive:
            base = destructiveFill
        }
        return configuration.isPressed ? base.opacity(0.82) : base
    }

    private var strokeColor: Color {
        let base: Color
        switch tone {
        case .neutral:     base = activeStroke
        case .accent:      base = isSelected ? accentFill.opacity(0.92) : activeStroke
        case .destructive: base = Color.red.opacity(isDarkMode ? 0.28 : 0.22)
        }
        return configuration.isPressed ? base.opacity(0.86) : base
    }

    private var foregroundColor: Color {
        let base: Color
        switch tone {
        case .accent where isSelected: base = .white
        case .destructive:             base = isDarkMode ? .white.opacity(0.92) : .red.opacity(0.8)
        default:                       base = isDarkMode ? .white.opacity(0.92) : .black.opacity(0.78)
        }
        return configuration.isPressed ? base.opacity(0.88) : base
    }

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 10.5 : 11, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, compact ? 9 : 10)
            .padding(.vertical, compact ? 5 : 6)
            .frame(minHeight: compact ? 0 : (minimumHeight ?? 29))
            .background(Capsule().fill(backgroundColor))
            .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}
