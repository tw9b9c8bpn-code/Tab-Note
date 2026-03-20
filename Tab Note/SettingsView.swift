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
    case advanced = "Advanced"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:    return "gear"
        case .appearance: return "paintbrush"
        case .behavior:   return "slider.horizontal.3"
        case .data:       return "internaldrive"
        case .advanced:   return "cpu"
        case .about:      return "info.circle"
        }
    }

    var intro: String {
        switch self {
        case .general:    return "Configure your global shortcut and startup preferences."
        case .appearance: return "Customize how Tab Note looks and feels."
        case .behavior:   return "Control window placement and layout density."
        case .data:       return "Recover or permanently remove deleted notes."
        case .advanced:   return "Configure AI providers, models, and connection profiles."
        case .about:      return "App information and update preferences."
        }
    }
}

// MARK: - AI Sub-Tab

private enum AISettingsTab: String, CaseIterable, Identifiable {
    case local = "Local"
    case api = "API"
    case saved = "Saved"

    var id: String { rawValue }
}

// MARK: - Health Status

private struct SavedModelHealthStatus {
    enum State { case idle, testing, success, failure }
    let state: State
    let message: String?
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
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(isDarkMode ? accentColor.opacity(0.16) : accentColor.opacity(0.10))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main View

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var store: NotesStore
    @Environment(\.dismiss) private var dismiss

    let onClose: (() -> Void)?

    @State private var selectedSection: SettingsSection = .general
    @State private var selectedAISettingsTab: AISettingsTab = .local

    @State private var isDiagnosing = false
    @State private var diagnoseResult = ""
    @State private var diagnoseStatus = ""
    @State private var availableLocalModels: [String] = []
    @State private var isLoadingLocalModels = false
    @State private var localModelsStatus = ""
    @State private var showsAPIKey = false
    @State private var apiProfileNameDraft = ""
    @State private var apiProfileStatus = ""
    @State private var advancedJSONStatus = ""
    @State private var showsDiagnosticsPopup = false
    @State private var diagnosticsPopupTitle = ""
    @State private var diagnosticsPopupSubtitle = ""
    @State private var savedModelHealthStatuses: [String: SavedModelHealthStatus] = [:]

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            panelBackground

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 172)

                Rectangle()
                    .fill(dividerColor)
                    .frame(width: 1)

                detailPanel
            }

            if showsDiagnosticsPopup {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        AIDiagnosticsPopup(
                            title: diagnosticsPopupTitle.isEmpty ? aiDiagnosticsButtonTitle : diagnosticsPopupTitle,
                            subtitle: diagnosticsPopupSubtitle.isEmpty ? diagnosticsSubtitleText : diagnosticsPopupSubtitle,
                            status: diagnoseStatus,
                            result: diagnoseResult,
                            isDiagnosing: isDiagnosing,
                            isDarkMode: settings.isDarkMode,
                            onCopy: copyDiagnosticsToPasteboard,
                            onClose: { showsDiagnosticsPopup = false }
                        )
                    }
                    .padding(Spacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(10)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            selectedAISettingsTab = settings.aiModeEnum == .local ? .local : .api
            if availableLocalModels.isEmpty {
                availableLocalModels = settings.cachedLocalModelNames
            }
            if settings.aiModeEnum == .local && availableLocalModels.isEmpty {
                refreshLocalModels()
            }
            syncAPIProfileDraft()
        }
        .onChange(of: settings.aiAPISelectedProfileID) { _, _ in
            syncAPIProfileDraft()
        }
        .onChange(of: settings.aiModeEnum) { _, newMode in
            resetAIDiagnostics()
            if selectedAISettingsTab != .saved {
                selectedAISettingsTab = newMode == .local ? .local : .api
            }
            if newMode == .local {
                refreshLocalModels()
            } else {
                syncAPIProfileDraft()
            }
        }
        .onChange(of: settings.aiAPIRequestStyleEnum) { _, newStyle in
            resetAIDiagnostics()
            advancedJSONStatus = ""
            if newStyle == .json,
               settings.aiAPIAdvancedJSONConfiguration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.aiAPIAdvancedJSONConfiguration = SettingsManager.defaultAdvancedAPIJSONConfiguration
            }
        }
        .onChange(of: selectedAISettingsTab) { _, newTab in
            if newTab == .saved && availableLocalModels.isEmpty {
                availableLocalModels = settings.cachedLocalModelNames
            }
            if newTab == .saved && availableLocalModels.isEmpty {
                refreshLocalModels()
            }
        }
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
                ForEach(SettingsSection.allCases) { section in
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

            Button(action: closeSettings) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(fieldFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(outlineColor, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
            .help("Close Settings")
        }
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                pageHeader
                sectionContent
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 680, alignment: .leading)
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
        case .advanced:   advancedSection
        case .about:      aboutSection
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(spacing: Spacing.lg) {
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
        VStack(spacing: Spacing.lg) {
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
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        VStack(spacing: Spacing.lg) {
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
        VStack(spacing: Spacing.lg) {
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

    // MARK: - Advanced (AI)

    private var advancedSection: some View {
        VStack(spacing: Spacing.lg) {
            settingsCard {
                HStack {
                    Spacer()
                    mergedSegmentedControl(
                        selection: Binding(
                            get: { selectedAISettingsTab },
                            set: { newTab in
                                selectedAISettingsTab = newTab
                                switch newTab {
                                case .local: settings.aiModeEnum = .local
                                case .api:   settings.aiModeEnum = .api
                                case .saved: syncAPIProfileDraft()
                                }
                            }
                        ),
                        options: AISettingsTab.allCases.map { ($0.rawValue, $0) }
                    )
                    Spacer()
                }
            }

            if selectedAISettingsTab == .local {
                localAISettingsCard
            } else if selectedAISettingsTab == .api {
                apiSettingsCard
            } else {
                savedProfilesCard
            }
        }
    }

    private var localAISettingsCard: some View {
        settingsCard {
            HStack(alignment: .top, spacing: Spacing.xs) {
                sectionHeader(
                    "Local Connection",
                    subtitle: "Edit your local endpoint and model details here. Active local-model selection now happens in Saved."
                )
                Spacer(minLength: Spacing.xs)
                diagnosticsButton
            }

            labeledInput("Local Endpoint") {
                textInput(placeholder: "http://localhost:11434", text: Binding(
                    get: { settings.aiLocalEndpoint },
                    set: { settings.aiLocalEndpoint = $0 }
                ))
            }

            labeledInput("Model Name") {
                textInput(placeholder: "e.g. llama3", text: Binding(
                    get: { settings.aiLocalModel },
                    set: { settings.aiLocalModel = $0 }
                ))
            }

            Button(action: refreshLocalModels) {
                HStack(spacing: Spacing.xxs) {
                    if isLoadingLocalModels {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(isLoadingLocalModels ? "Refreshing Local Models..." : "Refresh Local Models")
                }
            }
            .buttonStyle(SettingsPillButtonStyle(isDarkMode: settings.isDarkMode, tone: .neutral, isSelected: false))
            .disabled(isLoadingLocalModels)

            if !localModelsStatus.isEmpty {
                Text(localModelsStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
            }
        }
    }

    private var apiSettingsCard: some View {
        settingsCard {
            sectionHeader(
                "API Connection",
                subtitle: "Edit API details here, then test. A successful test saves a new preset when the configuration name is new, or updates the matching saved model."
            )

            labeledInput("Configuration Name") {
                inlineActionInput(
                    placeholder: "Preset name",
                    text: $apiProfileNameDraft,
                    actionLabel: isDiagnosing ? "Testing" : "Test",
                    actionSystemImage: isDiagnosing ? nil : "stethoscope",
                    actionEmphasis: true,
                    isActionInProgress: isDiagnosing,
                    action: { testAPIConfigurationFromEntry() }
                )
                .disabled(isDiagnosing || !canSaveAPIProfile)
            }

            Text(settings.aiSelectedAPIProfile.map { "Editing saved preset: \($0.name)" } ?? "Successful tests save here automatically. Pick the active preset from Saved.")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor)

            if !apiProfileStatus.isEmpty {
                Text(apiProfileStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
            }

            Divider()

            labeledInput("Request Style") {
                choiceStrip(
                    selection: Binding(
                        get: { settings.aiAPIRequestStyleEnum },
                        set: { settings.aiAPIRequestStyleEnum = $0 }
                    ),
                    options: APIRequestStyle.allCases.map { ($0.displayName, $0) }
                )
            }

            if settings.aiAPIRequestStyleEnum == .standard {
                standardAPIFields
            } else {
                advancedJSONSection
            }
        }
    }

    private var savedProfilesCard: some View {
        settingsCard {
            HStack(alignment: .top, spacing: Spacing.xs) {
                sectionHeader(
                    "Saved Models",
                    subtitle: "Selection lives here. Local models and saved API presets stay side by side with inline health icons."
                )
                Spacer(minLength: Spacing.xs)
                Button(action: runSavedProfilesHealthTest) {
                    HStack(spacing: Spacing.xxs) {
                        if isDiagnosing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isDiagnosing ? "Testing" : "Test All")
                    }
                }
                .buttonStyle(SettingsPillButtonStyle(isDarkMode: settings.isDarkMode, tone: .accent, isSelected: false, compact: true))
                .disabled(isDiagnosing || (settings.aiAPISavedProfiles.isEmpty && availableLocalModels.isEmpty))
            }

            if isDiagnosing {
                Text(diagnoseStatus.isEmpty ? "Testing saved models..." : diagnoseStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
            }

            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text("LOCAL MODELS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)

                        Spacer()

                        Button(action: refreshLocalModels) {
                            HStack(spacing: Spacing.xxs) {
                                if isLoadingLocalModels {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                Text(isLoadingLocalModels ? "Refreshing" : "Refresh")
                            }
                        }
                        .buttonStyle(SettingsPillButtonStyle(isDarkMode: settings.isDarkMode, tone: .neutral, isSelected: false, compact: true))
                        .disabled(isLoadingLocalModels)
                    }

                    if availableLocalModels.isEmpty {
                        Text(localModelsStatus.isEmpty ? "No local models loaded yet." : localModelsStatus)
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryTextColor)
                    } else {
                        LazyVStack(spacing: Spacing.xs) {
                            ForEach(availableLocalModels, id: \.self) { modelName in
                                savedLocalModelRow(modelName)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("SAVED API MODELS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    if settings.aiAPISavedProfiles.isEmpty {
                        VStack(spacing: Spacing.xs) {
                            Text("No saved API models yet")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(primaryTextColor)

                            Text("Test a setup from the API tab and it will appear here automatically.")
                                .font(.system(size: 12))
                                .foregroundStyle(secondaryTextColor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.xxs)
                    } else {
                        LazyVStack(spacing: Spacing.xs) {
                            ForEach(settings.aiAPISavedProfiles) { profile in
                                savedAPIProfileRow(profile)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if !apiProfileStatus.isEmpty {
                Text(apiProfileStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: Spacing.lg) {
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

    // MARK: - Saved Profile Rows

    private func savedLocalModelRow(_ modelName: String) -> some View {
        let isSelected = settings.aiModeEnum == .local
            && settings.aiLocalModel.trimmingCharacters(in: .whitespacesAndNewlines) == modelName

        return savedSelectionCard(
            title: modelName,
            detail: "Local | \(savedProfileEndpointLabel(for: settings.aiLocalEndpoint))",
            isSelected: isSelected,
            healthStatus: savedModelHealthStatuses[localHealthKey(for: modelName)],
            reserveTrailingSpace: 30
        ) {
            activateLocalSavedModel(modelName)
        } trailing: {
            savedHealthAccessory(
                for: savedModelHealthStatuses[localHealthKey(for: modelName)],
                title: modelName,
                subtitle: "Local | \(savedProfileEndpointLabel(for: settings.aiLocalEndpoint))"
            )
        }
    }

    private func savedAPIProfileRow(_ profile: AIAPIProfile) -> some View {
        savedSelectionCard(
            title: profile.name,
            detail: savedProfileDetailLine(for: profile),
            isSelected: settings.aiSelectedAPIProfile?.id == profile.id && settings.aiModeEnum == .api,
            healthStatus: savedModelHealthStatuses[apiHealthKey(for: profile)],
            reserveTrailingSpace: 74
        ) {
            activateSavedProfile(profile)
        } trailing: {
            HStack(spacing: Spacing.xs) {
                savedHealthAccessory(
                    for: savedModelHealthStatuses[apiHealthKey(for: profile)],
                    title: profile.name,
                    subtitle: savedProfileDetailLine(for: profile)
                )
                compactIconButton(systemImage: "pencil", tint: primaryTextColor.opacity(0.85)) {
                    editSavedProfile(profile)
                }
                compactIconButton(systemImage: "trash", tint: Color.red.opacity(settings.isDarkMode ? 0.82 : 0.78)) {
                    deleteSavedProfile(profile)
                }
            }
        }
    }

    private func savedSelectionCard<Trailing: View>(
        title: String,
        detail: String,
        isSelected: Bool,
        healthStatus: SavedModelHealthStatus?,
        reserveTrailingSpace: CGFloat,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: Spacing.xs) {
                                Text(title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(primaryTextColor)
                                    .lineLimit(1)

                                if isSelected {
                                    Text("Active")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(accentColor))
                                }
                            }

                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(2)
                        }

                        Spacer(minLength: reserveTrailingSpace)
                    }

                    if let healthText = savedHealthStatusText(for: healthStatus), !healthText.isEmpty {
                        Text(healthText)
                            .font(.system(size: 10.5))
                            .foregroundStyle(savedHealthStatusColor(for: healthStatus))
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, Spacing.sm - 2)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(isSelected ? accentColor.opacity(settings.isDarkMode ? 0.14 : 0.10) : fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(isSelected ? accentColor.opacity(0.75) : outlineColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            trailing()
                .padding(.top, Spacing.xs)
                .padding(.trailing, Spacing.xs)
        }
    }

    // MARK: - API Fields

    private var standardAPIFields: some View {
        Group {
            labeledInput("API Key") {
                HStack(spacing: Spacing.xs) {
                    if showsAPIKey {
                        textInput(placeholder: "Enter API key", text: Binding(
                            get: { settings.aiApiKey },
                            set: { settings.aiApiKey = $0 }
                        ))
                    } else {
                        secureInput(placeholder: "Enter API key", text: Binding(
                            get: { settings.aiApiKey },
                            set: { settings.aiApiKey = $0 }
                        ))
                    }

                    Button {
                        showsAPIKey.toggle()
                    } label: {
                        Image(systemName: showsAPIKey ? "eye.slash" : "eye")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(SettingsPillButtonStyle(isDarkMode: settings.isDarkMode, tone: .neutral, isSelected: false, compact: true))
                }
            }

            Text("If the error says the key ends with `/v1`, the API Key field contains your endpoint instead of the real secret key.")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor)

            labeledInput("API Header") {
                textInput(placeholder: "Authorization", text: Binding(
                    get: { settings.aiAPIHeaderName },
                    set: { settings.aiAPIHeaderName = $0 }
                ))
            }

            labeledInput("API Endpoint") {
                textInput(placeholder: "https://api.openai.com/v1", text: Binding(
                    get: { settings.aiAPIEndpoint },
                    set: { settings.aiAPIEndpoint = $0 }
                ))
            }

            labeledInput("Model Name") {
                textInput(placeholder: "e.g. gpt-5-nano", text: Binding(
                    get: { settings.aiAPIModel },
                    set: { settings.aiAPIModel = $0 }
                ))
            }

            Text("Supports OpenAI-compatible `/v1` bases and Anthropic-compatible `/anthropic` bases.")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor)
        }
    }

    private var advancedJSONSection: some View {
        Group {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Advanced JSON")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Text("Paste a full request definition. Prompt presets only apply when the body includes the prompt placeholders.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(secondaryTextColor)
            }

            HStack(spacing: Spacing.xs) {
                Button("Use Example") {
                    settings.aiAPIAdvancedJSONConfiguration = SettingsManager.defaultAdvancedAPIJSONConfiguration
                    resetAIDiagnostics()
                }
                .buttonStyle(SettingsPillButtonStyle(isDarkMode: settings.isDarkMode, tone: .accent, isSelected: false))

                Button("Format JSON") { formatAdvancedJSONConfiguration() }
                    .buttonStyle(SettingsPillButtonStyle(isDarkMode: settings.isDarkMode, tone: .neutral, isSelected: false))
            }

            TextEditor(text: Binding(
                get: { settings.aiAPIAdvancedJSONConfiguration },
                set: { settings.aiAPIAdvancedJSONConfiguration = $0 }
            ))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(primaryTextColor)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 220, maxHeight: 220)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )

            Text("Use `{{system_prompt}}` and `{{user_message}}` if you want Tab Note's prompt presets to flow into JSON mode. Common OpenAI/Anthropic response shapes are auto-detected, otherwise add `response.text_path` manually. Other placeholders: `{{stream}}`, `{{temperature}}`, `{{max_tokens}}`, `{{max_completion_tokens}}`.")
                .font(.system(size: 11))
                .foregroundStyle(secondaryTextColor)

            if !advancedJSONStatus.isEmpty {
                Text(advancedJSONStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryTextColor)
            }
        }
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
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
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
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(primaryTextColor)
    }

    private func labeledInput<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            fieldLabel(title)
            content()
        }
    }

    private func textInput(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, Spacing.sm - 2)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
    }

    private func secureInput(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, Spacing.sm - 2)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
    }

    private func inlineActionInput(
        placeholder: String,
        text: Binding<String>,
        actionLabel: String,
        actionSystemImage: String?,
        actionEmphasis: Bool = false,
        isActionInProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Spacing.xs) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(primaryTextColor)

            Button(action: action) {
                HStack(spacing: Spacing.xxs) {
                    if isActionInProgress {
                        ProgressView().controlSize(.small)
                    } else if let actionSystemImage {
                        Image(systemName: actionSystemImage)
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    Text(actionLabel)
                }
            }
            .buttonStyle(SettingsPillButtonStyle(
                isDarkMode: settings.isDarkMode,
                tone: actionEmphasis ? .accent : .neutral,
                isSelected: false,
                compact: true
            ))
            .disabled(isActionInProgress)
        }
        .padding(.horizontal, Spacing.sm - 2)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                .fill(fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg - 3, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
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

    private func compactIconButton(
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(fieldFill.opacity(settings.isDarkMode ? 1 : 0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(outlineColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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

            choiceStrip(selection: selection, options: options)
        }
    }

    private func choiceStrip<Value: Hashable>(
        selection: Binding<Value>,
        options: [(String, Value)]
    ) -> some View {
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

    private func mergedSegmentedControl<Value: Hashable>(
        selection: Binding<Value>,
        options: [(String, Value)]
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { index in
                let option = options[index]
                let isSelected = selection.wrappedValue == option.1
                Button(option.0) {
                    selection.wrappedValue = option.1
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : primaryTextColor.opacity(0.88))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs + 1)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
                .background(
                    segmentBackground(isSelected: isSelected, index: index, count: options.count)
                )
            }
        }
        .padding(2)
        .background(Capsule().fill(fieldFill))
        .overlay(Capsule().stroke(outlineColor, lineWidth: 1))
    }

    @ViewBuilder
    private func segmentBackground(isSelected: Bool, index: Int, count: Int) -> some View {
        if isSelected {
            UnevenRoundedRectangle(
                topLeadingRadius: index == 0 ? 999 : Radius.sm,
                bottomLeadingRadius: index == 0 ? 999 : Radius.sm,
                bottomTrailingRadius: index == count - 1 ? 999 : Radius.sm,
                topTrailingRadius: index == count - 1 ? 999 : Radius.sm,
                style: .continuous
            )
            .fill(accentColor)
        } else {
            Color.clear
        }
    }

    // MARK: - Health Indicators

    private func savedProfileDetailLine(for profile: AIAPIProfile) -> String {
        let modelText = savedProfileModelName(for: profile)
        let endpointText = savedProfileEndpointLabel(for: profile)
        return [profile.requestStyle.displayName, modelText, endpointText]
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }

    private func healthStatusIcon(for status: SavedModelHealthStatus?) -> some View {
        let resolvedStatus = status ?? SavedModelHealthStatus(state: .idle, message: nil)
        let symbolName: String
        let tint: Color

        switch resolvedStatus.state {
        case .idle:
            symbolName = "circle.dashed"
            tint = secondaryTextColor.opacity(0.55)
        case .testing:
            symbolName = "clock.arrow.circlepath"
            tint = secondaryTextColor
        case .success:
            symbolName = "checkmark.circle.fill"
            tint = Color.green.opacity(settings.isDarkMode ? 0.92 : 0.84)
        case .failure:
            symbolName = "xmark.circle.fill"
            tint = Color.red.opacity(settings.isDarkMode ? 0.92 : 0.80)
        }

        return Image(systemName: symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private func savedHealthAccessory(
        for status: SavedModelHealthStatus?,
        title: String,
        subtitle: String
    ) -> some View {
        let resolvedStatus = status ?? SavedModelHealthStatus(state: .idle, message: nil)

        switch resolvedStatus.state {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
        case .success:
            healthStatusIcon(for: resolvedStatus)
        case .failure:
            Button {
                diagnoseStatus = "Failed"
                diagnoseResult = resolvedStatus.message ?? "The saved model health check failed."
                presentDiagnosticsPopup(title: title, subtitle: subtitle)
            } label: {
                healthStatusIcon(for: resolvedStatus)
            }
            .buttonStyle(.plain)
            .help("Show failure details")
        }
    }

    private func savedHealthStatusText(for status: SavedModelHealthStatus?) -> String? {
        guard let status else { return nil }
        switch status.state {
        case .idle, .success, .failure: return nil
        case .testing: return "Testing..."
        }
    }

    private func savedHealthStatusColor(for status: SavedModelHealthStatus?) -> Color {
        guard let status else { return secondaryTextColor }
        switch status.state {
        case .idle, .testing: return secondaryTextColor
        case .success: return Color.green.opacity(settings.isDarkMode ? 0.9 : 0.78)
        case .failure: return Color.red.opacity(settings.isDarkMode ? 0.9 : 0.78)
        }
    }

    private func apiHealthKey(for profile: AIAPIProfile) -> String { "api:\(profile.id)" }
    private func localHealthKey(for modelName: String) -> String { "local:\(modelName)" }

    private func savedProfileModelName(for profile: AIAPIProfile) -> String {
        let trimmedModel = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty { return trimmedModel }
        if profile.requestStyle == .json {
            return extractedModelName(fromAdvancedJSONConfiguration: profile.advancedJSONConfiguration) ?? "JSON template"
        }
        return "Model not set"
    }

    private func savedProfileEndpointLabel(for profile: AIAPIProfile) -> String {
        let trimmedEndpoint = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: trimmedEndpoint)?.host, !host.isEmpty { return host }
        return trimmedEndpoint.isEmpty ? "Endpoint not set" : trimmedEndpoint
    }

    private func savedProfileEndpointLabel(for endpoint: String) -> String {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: trimmedEndpoint)?.host, !host.isEmpty { return host }
        return trimmedEndpoint.isEmpty ? "Endpoint not set" : trimmedEndpoint
    }

    private func extractedModelName(fromAdvancedJSONConfiguration rawConfiguration: String) -> String? {
        let trimmed = rawConfiguration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any],
              let body = json["body"] as? [String: Any],
              let model = body["model"] as? String else { return nil }
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    // MARK: - Actions

    private func closeSettings() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var aiDiagnosticsButtonTitle: String {
        settings.aiModeEnum == .local ? "Test Local Server" : "Test API Connection"
    }

    private var diagnosticsButton: some View {
        Button(action: runLocalDiagnosticsFromHeader) {
            HStack(spacing: Spacing.xxs) {
                if isDiagnosing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isDiagnosing ? "Testing" : "Test")
            }
        }
        .buttonStyle(SettingsPillButtonStyle(isDarkMode: settings.isDarkMode, tone: .accent, isSelected: false, compact: true))
        .disabled(isDiagnosing)
    }

    private func runActiveConfigurationTest(autoSaveAPIProfileOnSuccess: Bool) {
        isDiagnosing = true
        diagnoseResult = ""
        diagnoseStatus = "Connecting..."

        AIService.shared.diagnose(
            settings: settings,
            onStatus: { status in
                DispatchQueue.main.async { diagnoseStatus = status }
            },
            completion: { result in
                DispatchQueue.main.async {
                    isDiagnosing = false
                    switch result {
                    case .success(let info):
                        var resolvedInfo = info
                        if autoSaveAPIProfileOnSuccess && settings.aiModeEnum == .api {
                            let profile = settings.upsertCurrentAPIProfile(named: apiProfileNameDraft)
                            apiProfileNameDraft = profile.name
                            apiProfileStatus = "Test passed and saved \(profile.name)."
                            resolvedInfo += "\n\nSaved as: \(profile.name)"
                        }
                        diagnoseResult = resolvedInfo
                        diagnoseStatus = autoSaveAPIProfileOnSuccess && settings.aiModeEnum == .api
                            ? "Connected and saved"
                            : "Connected"
                    case .failure(let error):
                        diagnoseResult = "X \(error.localizedDescription)"
                        diagnoseStatus = "Failed"
                    }
                }
            }
        )
    }

    private func runLocalDiagnosticsFromHeader() {
        diagnoseStatus = ""
        diagnoseResult = ""
        presentDiagnosticsPopup(title: aiDiagnosticsButtonTitle, subtitle: diagnosticsSubtitleText)
        runActiveConfigurationTest(autoSaveAPIProfileOnSuccess: false)
    }

    private func testAPIConfigurationFromEntry() {
        diagnoseStatus = ""
        diagnoseResult = ""
        presentDiagnosticsPopup(
            title: "Test API Connection",
            subtitle: "Runs the active API configuration, then auto-saves the matching preset if the test succeeds."
        )
        runActiveConfigurationTest(autoSaveAPIProfileOnSuccess: true)
    }

    private func refreshLocalModels() {
        isLoadingLocalModels = true
        localModelsStatus = ""

        AIService.shared.fetchLocalModels(endpoint: settings.aiLocalEndpoint) { result in
            DispatchQueue.main.async {
                isLoadingLocalModels = false
                switch result {
                case .success(let models):
                    availableLocalModels = models
                    settings.cachedLocalModelNames = models
                    savedModelHealthStatuses = savedModelHealthStatuses.filter { key, _ in
                        !key.hasPrefix("local:") || models.contains(String(key.dropFirst("local:".count)))
                    }
                    localModelsStatus = models.isEmpty
                        ? "No local models were returned by the current endpoint."
                        : "\(models.count) local model\(models.count == 1 ? "" : "s") found."
                case .failure(let error):
                    availableLocalModels = settings.cachedLocalModelNames
                    savedModelHealthStatuses = savedModelHealthStatuses.filter { key, _ in
                        !key.hasPrefix("local:") || availableLocalModels.contains(String(key.dropFirst("local:".count)))
                    }
                    localModelsStatus = "Could not load local models: \(error.localizedDescription)"
                }
            }
        }
    }

    private func resetAIDiagnostics() {
        isDiagnosing = false
        diagnoseResult = ""
        diagnoseStatus = ""
        showsDiagnosticsPopup = false
        diagnosticsPopupTitle = ""
        diagnosticsPopupSubtitle = ""
    }

    private var canSaveAPIProfile: Bool {
        let trimmedName = apiProfileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return true }
        switch settings.aiAPIRequestStyleEnum {
        case .standard:
            let endpoint = settings.aiAPIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = settings.aiAPIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let apiKey = settings.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return !endpoint.isEmpty && !model.isEmpty && !apiKey.isEmpty
        case .json:
            return !settings.aiAPIAdvancedJSONConfiguration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func syncAPIProfileDraft() {
        apiProfileNameDraft = settings.aiSelectedAPIProfile?.name ?? settings.suggestedAPIProfileName()
    }

    private func selectAPIProfile(_ id: String) {
        if id.isEmpty {
            settings.aiAPISelectedProfileID = nil
            apiProfileStatus = "Current API fields are unsaved."
            syncAPIProfileDraft()
            return
        }
        guard settings.applyAPIProfile(id: id), let profile = settings.aiSelectedAPIProfile else { return }
        apiProfileNameDraft = profile.name
        apiProfileStatus = "Loaded \(profile.name)."
        resetAIDiagnostics()
    }

    private func activateLocalSavedModel(_ modelName: String) {
        settings.aiModeEnum = .local
        settings.aiLocalModel = modelName
        settings.cachedLocalModelNames = settings.cachedLocalModelNames + [modelName]
        apiProfileStatus = "Selected local model \(modelName)."
        resetAIDiagnostics()
    }

    private func activateSavedProfile(_ profile: AIAPIProfile) {
        settings.aiModeEnum = .api
        selectAPIProfile(profile.id)
        apiProfileStatus = "Selected \(profile.name) as the active saved model."
    }

    private func editSavedProfile(_ profile: AIAPIProfile) {
        activateSavedProfile(profile)
        selectedAISettingsTab = .api
        apiProfileStatus = "Editing \(profile.name) in the API tab."
    }

    private func deleteSavedProfile(_ profile: AIAPIProfile) {
        guard let removed = settings.deleteAPIProfile(id: profile.id) else { return }
        savedModelHealthStatuses.removeValue(forKey: apiHealthKey(for: profile))
        if settings.aiSelectedAPIProfile == nil { syncAPIProfileDraft() }
        apiProfileStatus = "Deleted \(removed.name)."
        resetAIDiagnostics()
    }

    private func formatAdvancedJSONConfiguration() {
        let trimmed = settings.aiAPIAdvancedJSONConfiguration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let formattedData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .fragmentsAllowed]),
              let formattedString = String(data: formattedData, encoding: .utf8) else {
            advancedJSONStatus = "Could not format JSON."
            return
        }
        settings.aiAPIAdvancedJSONConfiguration = formattedString
        advancedJSONStatus = "Formatted advanced JSON."
    }

    private func presentDiagnosticsPopup(title: String, subtitle: String) {
        diagnosticsPopupTitle = title
        diagnosticsPopupSubtitle = subtitle
        showsDiagnosticsPopup = true
    }

    private func runSavedProfilesHealthTest() {
        let localModels = availableLocalModels.isEmpty ? settings.cachedLocalModelNames : availableLocalModels
        let profiles = settings.aiAPISavedProfiles
        guard !profiles.isEmpty || !localModels.isEmpty else {
            isDiagnosing = false
            diagnoseStatus = "Nothing to test"
            diagnoseResult = "No saved models are available."
            return
        }

        isDiagnosing = true
        diagnoseResult = ""
        savedModelHealthStatuses = Dictionary(uniqueKeysWithValues: (
            profiles.map { (apiHealthKey(for: $0), SavedModelHealthStatus(state: .testing, message: nil)) }
            + localModels.map { (localHealthKey(for: $0), SavedModelHealthStatus(state: .testing, message: nil)) }
        ))
        diagnoseStatus = "Testing 1 of \(profiles.count + localModels.count)..."
        runSavedProfilesHealthTest(localModels: localModels, profiles: profiles, index: 0, reports: [])
    }

    private func runSavedProfilesHealthTest(
        localModels: [String],
        profiles: [AIAPIProfile],
        index: Int,
        reports: [String]
    ) {
        let totalCount = localModels.count + profiles.count
        guard index < totalCount else {
            isDiagnosing = false
            diagnoseStatus = "Completed"
            diagnoseResult = reports.joined(separator: "\n\n----------------\n\n")
            return
        }

        if index < localModels.count {
            let modelName = localModels[index]
            diagnoseStatus = "Testing \(index + 1) of \(totalCount): \(modelName)"

            AIService.shared.diagnoseLocalModel(endpoint: settings.aiLocalEndpoint, model: modelName) { result in
                var updatedReports = reports
                let healthKey = localHealthKey(for: modelName)
                switch result {
                case .success(let info):
                    savedModelHealthStatuses[healthKey] = SavedModelHealthStatus(state: .success, message: "Healthy")
                    updatedReports.append("[OK] \(modelName) | Local\n\(info)")
                case .failure(let error):
                    let message = error.localizedDescription
                    savedModelHealthStatuses[healthKey] = SavedModelHealthStatus(state: .failure, message: message)
                    updatedReports.append("[Failed] \(modelName) | Local\n\(message)")
                }
                runSavedProfilesHealthTest(localModels: localModels, profiles: profiles, index: index + 1, reports: updatedReports)
            }
            return
        }

        let profileIndex = index - localModels.count
        let profile = profiles[profileIndex]
        diagnoseStatus = "Testing \(index + 1) of \(totalCount): \(profile.name)"

        AIService.shared.diagnose(profile: profile) { result in
            var updatedReports = reports
            let header = "\(profile.name) | \(profile.requestStyle.displayName) | \(self.savedProfileModelName(for: profile))"
            let healthKey = apiHealthKey(for: profile)
            switch result {
            case .success(let info):
                savedModelHealthStatuses[healthKey] = SavedModelHealthStatus(state: .success, message: "Healthy")
                updatedReports.append("[OK] \(header)\n\(info)")
            case .failure(let error):
                let message = error.localizedDescription
                savedModelHealthStatuses[healthKey] = SavedModelHealthStatus(state: .failure, message: message)
                updatedReports.append("[Failed] \(header)\n\(message)")
            }
            runSavedProfilesHealthTest(localModels: localModels, profiles: profiles, index: index + 1, reports: updatedReports)
        }
    }

    private func copyDiagnosticsToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsTranscript, forType: .string)
    }

    private var diagnosticsTranscript: String {
        let trimmedStatus = diagnoseStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResult = diagnoseResult.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedStatus.isEmpty && trimmedResult.isEmpty {
            return "Run a test to inspect the active AI configuration."
        }
        return [trimmedStatus.isEmpty ? nil : "Status: \(trimmedStatus)", trimmedResult.isEmpty ? nil : trimmedResult]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    private let hotkeyKeys: [(Int, String)] = SettingsManager.hotkeyKeyNames
        .map { ($0.key, $0.value) }
        .sorted { $0.1 < $1.1 }

    private var diagnosticsSubtitleText: String {
        switch settings.aiModeEnum {
        case .local:
            return "Checks the local endpoint and fetches the available model list."
        case .api where settings.aiAPIRequestStyleEnum == .json:
            return "Executes the pasted JSON request definition with the connectivity test prompts."
        case .api:
            return "Sends a real provider-aware API request using the active endpoint, header, and model."
        }
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

    private var accentFill: Color {
        isDarkMode ? Color(red: 0.89, green: 0.49, blue: 0.18) : Color(red: 0.90, green: 0.50, blue: 0.16)
    }
    private var neutralFill: Color {
        isDarkMode ? .white.opacity(0.06) : .white.opacity(0.84)
    }
    private var destructiveFill: Color {
        isDarkMode ? Color.red.opacity(0.18) : Color.red.opacity(0.10)
    }
    private var activeStroke: Color {
        isDarkMode ? .white.opacity(0.10) : .black.opacity(0.08)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 10.5 : 11, weight: .semibold))
            .foregroundStyle(foregroundColor(configuration: configuration))
            .padding(.horizontal, compact ? 9 : 10)
            .padding(.vertical, compact ? 5 : 6)
            .frame(minHeight: compact ? 0 : (minimumHeight ?? 29))
            .background(Capsule().fill(backgroundColor(configuration: configuration)))
            .overlay(Capsule().stroke(strokeColor(configuration: configuration), lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        let base: Color
        switch tone {
        case .neutral:     base = neutralFill
        case .accent:      base = isSelected ? accentFill : neutralFill
        case .destructive: base = destructiveFill
        }
        return configuration.isPressed ? base.opacity(0.85) : base
    }

    private func strokeColor(configuration: Configuration) -> Color {
        let base: Color
        switch tone {
        case .neutral:     base = activeStroke
        case .accent:      base = isSelected ? accentFill.opacity(0.92) : activeStroke
        case .destructive: base = Color.red.opacity(isDarkMode ? 0.28 : 0.22)
        }
        return configuration.isPressed ? base.opacity(0.86) : base
    }

    private func foregroundColor(configuration: Configuration) -> Color {
        let base: Color
        switch tone {
        case .accent where isSelected: base = .white
        case .destructive:             base = isDarkMode ? .white.opacity(0.92) : .red.opacity(0.8)
        default:                       base = isDarkMode ? .white.opacity(0.92) : .black.opacity(0.78)
        }
        return configuration.isPressed ? base.opacity(0.88) : base
    }
}

// MARK: - Diagnostics Popup

private struct AIDiagnosticsPopup: View {
    let title: String
    let subtitle: String
    let status: String
    let result: String
    let isDiagnosing: Bool
    let isDarkMode: Bool
    let onCopy: () -> Void
    let onClose: () -> Void

    private var primaryTextColor: Color {
        isDarkMode ? .white.opacity(0.95) : .black.opacity(0.84)
    }

    private var secondaryTextColor: Color {
        isDarkMode ? .white.opacity(0.62) : .black.opacity(0.55)
    }

    private var fieldFill: Color {
        isDarkMode ? .white.opacity(0.05) : .white.opacity(0.88)
    }

    private var outlineColor: Color {
        isDarkMode ? .white.opacity(0.09) : .black.opacity(0.08)
    }

    private var displayedText: String {
        let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedStatus.isEmpty && trimmedResult.isEmpty {
            return "Waiting to run the AI connection test."
        }
        return [trimmedStatus.isEmpty ? nil : "Status: \(trimmedStatus)", trimmedResult.isEmpty ? nil : trimmedResult]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if isDiagnosing {
                        ProgressView().controlSize(.small)
                    }

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(SettingsPillButtonStyle(isDarkMode: isDarkMode, tone: .neutral, isSelected: false, compact: true))
                    .help("Copy to clipboard")

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(SettingsPillButtonStyle(isDarkMode: isDarkMode, tone: .neutral, isSelected: false, compact: true))
                }
            }

            ScrollView {
                Text(displayedText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(primaryTextColor.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 160)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
        }
        .padding(14)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isDarkMode
                    ? Color(red: 0.13, green: 0.13, blue: 0.15)
                    : Color(red: 0.96, green: 0.96, blue: 0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
        .shadow(
            color: isDarkMode ? .black.opacity(0.4) : .black.opacity(0.14),
            radius: 16, x: 0, y: 6
        )
    }
}
