//
//  SettingsView.swift
//  Tab Note
//
//  Created by Kien Tran on 2026-03-03.
//

import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case ai = "AI"
    case deletedNotes = "Deleted Notes"

    var id: String { rawValue }
}

private enum AISettingsTab: String, CaseIterable, Identifiable {
    case local = "Local"
    case api = "API"
    case saved = "Saved"

    var id: String { rawValue }
}

private struct SavedModelHealthStatus {
    enum State {
        case idle
        case testing
        case success
        case failure
    }

    let state: State
    let message: String?
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var store: NotesStore
    @Environment(\.dismiss) private var dismiss

    let onClose: (() -> Void)?

    @State private var selectedTab: SettingsTab = .general
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

            VStack(spacing: 8) {
                header
                tabBar

                ScrollView {
                    VStack(spacing: 8) {
                        selectedTabContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.never)
            }
            .padding(12)
            
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
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(10)
            }
        }
        .frame(minWidth: 560, minHeight: 520)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryTextColor)

                Text("Tune hotkeys, AI providers, and note recovery.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            Button(action: closeSettings) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(SettingsPillButtonStyle(
                isDarkMode: settings.isDarkMode,
                tone: .neutral,
                isSelected: false,
                compact: true
            ))
            .help("Close Settings")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            mergedSegmentedControl(
                selection: Binding(
                    get: { selectedTab },
                    set: { newTab in
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                            selectedTab = newTab
                        }
                    }
                ),
                options: [
                    (SettingsTab.general.rawValue, SettingsTab.general),
                    (SettingsTab.ai.rawValue, SettingsTab.ai)
                ]
            )

            Spacer(minLength: 8)

            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                    selectedTab = .deletedNotes
                }
            } label: {
                Text(SettingsTab.deletedNotes.rawValue)
            }
            .buttonStyle(SettingsPillButtonStyle(
                isDarkMode: settings.isDarkMode,
                tone: .accent,
                isSelected: selectedTab == .deletedNotes
            ))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            generalSettings
        case .ai:
            aiSettings
        case .deletedNotes:
            deletedNotesSettings
        }
    }

    private var generalSettings: some View {
        VStack(spacing: 8) {
            settingsCard {
                sectionHeader(
                    "Global Hotkey",
                    subtitle: "Choose the shortcut that reveals or hides Tab Note from anywhere."
                )

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Modifiers")
                    HStack(spacing: 6) {
                        modifierPill(label: "⌘ Cmd", flag: 0x0100)
                        modifierPill(label: "⇧ Shift", flag: 0x0200)
                        modifierPill(label: "⌥ Option", flag: 0x0800)
                        modifierPill(label: "⌃ Ctrl", flag: 0x1000)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Key")
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(hotkeyKeys, id: \.0) { code, label in
                                Button(label) {
                                    settings.hotkeyKeyCode = code
                                }
                            }
                        } label: {
                            fieldMenuLabel("Key: \(SettingsManager.hotkeyKeyNames[settings.hotkeyKeyCode] ?? "?")")
                        }
                        .menuStyle(.borderlessButton)

                        Text("Current shortcut: \(settings.hotkeyDisplayLabel)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }

            settingsCard {
                sectionHeader(
                    "Window Behavior",
                    subtitle: "Control where Tab Note appears and how dense the tab stack can get."
                )

                choiceGroup(
                    title: "Show Window",
                    subtitle: "Apply the reveal position to the main window and detached windows.",
                    selection: Binding(
                        get: { settings.positionModeEnum },
                        set: { settings.positionModeEnum = $0 }
                    ),
                    options: PositionMode.allCases.map { ($0.displayName, $0) }
                )

                choiceGroup(
                    title: "Max Tab Rows",
                    subtitle: "Keep the tab bar compact before it spills into more rows.",
                    selection: Binding(
                        get: { settings.maxTabRows },
                        set: { settings.maxTabRows = $0 }
                    ),
                    options: [("2 Rows", 2), ("3 Rows", 3), ("4 Rows", 4)]
                )
            }

            settingsCard {
                sectionHeader(
                    "App Behavior",
                    subtitle: "Set startup behavior and how updates are checked."
                )

                booleanChoiceGroup(
                    title: "Launch at Login",
                    subtitle: "Automatically start Tab Note when you log in.",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.launchAtLogin = $0 }
                    )
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Updates")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(primaryTextColor)
                            Text("Check for new versions from the Sparkle feed.")
                                .font(.system(size: 12))
                                .foregroundStyle(secondaryTextColor)
                        }

                        Spacer()

                        Button("Check for Updates") {
                            AppUpdater.shared.checkForUpdates()
                        }
                        .buttonStyle(SettingsPillButtonStyle(
                            isDarkMode: settings.isDarkMode,
                            tone: .accent,
                            isSelected: false
                        ))
                    }

                    booleanChoiceGroup(
                        title: "Auto-check on Launch",
                        subtitle: "Run an update check a few seconds after the app opens.",
                        isOn: Binding(
                            get: { settings.autoCheckUpdates },
                            set: { settings.autoCheckUpdates = $0 }
                        )
                    )
                }
            }
        }
    }

    private var aiSettings: some View {
        VStack(spacing: 8) {
            settingsCard {
                HStack {
                    Spacer()
                    mergedSegmentedControl(
                        selection: Binding(
                            get: { selectedAISettingsTab },
                            set: { newTab in
                                selectedAISettingsTab = newTab
                                switch newTab {
                                case .local:
                                    settings.aiModeEnum = .local
                                case .api:
                                    settings.aiModeEnum = .api
                                case .saved:
                                    syncAPIProfileDraft()
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
            HStack(alignment: .top, spacing: 8) {
                sectionHeader(
                    "Local Connection",
                    subtitle: "Edit your local endpoint and model details here. Active local-model selection now happens in Saved."
                )
                Spacer(minLength: 8)
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
                HStack(spacing: 4) {
                    if isLoadingLocalModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(isLoadingLocalModels ? "Refreshing Local Models..." : "Refresh Local Models")
                }
            }
            .buttonStyle(SettingsPillButtonStyle(
                isDarkMode: settings.isDarkMode,
                tone: .neutral,
                isSelected: false
            ))
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
            HStack(alignment: .top, spacing: 8) {
                sectionHeader(
                    "Saved Models",
                    subtitle: "Selection lives here. Local models and saved API presets stay side by side with inline health icons."
                )
                Spacer(minLength: 8)
                Button(action: runSavedProfilesHealthTest) {
                    HStack(spacing: 4) {
                        if isDiagnosing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isDiagnosing ? "Testing" : "Test All")
                    }
                }
                .buttonStyle(SettingsPillButtonStyle(
                    isDarkMode: settings.isDarkMode,
                    tone: .accent,
                    isSelected: false,
                    compact: true
                ))
                .disabled(isDiagnosing || (settings.aiAPISavedProfiles.isEmpty && availableLocalModels.isEmpty))
            }

            if isDiagnosing {
                Text(diagnoseStatus.isEmpty ? "Testing saved models..." : diagnoseStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("LOCAL MODELS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)

                        Spacer()

                        Button(action: refreshLocalModels) {
                            HStack(spacing: 4) {
                                if isLoadingLocalModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                Text(isLoadingLocalModels ? "Refreshing" : "Refresh")
                            }
                        }
                        .buttonStyle(SettingsPillButtonStyle(
                            isDarkMode: settings.isDarkMode,
                            tone: .neutral,
                            isSelected: false,
                            compact: true
                        ))
                        .disabled(isLoadingLocalModels)
                    }

                    if availableLocalModels.isEmpty {
                        Text(localModelsStatus.isEmpty ? "No local models loaded yet." : localModelsStatus)
                            .font(.system(size: 12))
                            .foregroundStyle(secondaryTextColor)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(availableLocalModels, id: \.self) { modelName in
                                savedLocalModelRow(modelName)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("SAVED API MODELS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    if settings.aiAPISavedProfiles.isEmpty {
                        VStack(spacing: 6) {
                            Text("No saved API models yet")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(primaryTextColor)

                            Text("Test a setup from the API tab and it will appear here automatically.")
                                .font(.system(size: 12))
                                .foregroundStyle(secondaryTextColor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    } else {
                        LazyVStack(spacing: 6) {
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
            HStack(spacing: 6) {
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
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
                                        .background(
                                            Capsule()
                                                .fill(accentColor)
                                        )
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
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? accentColor.opacity(settings.isDarkMode ? 0.14 : 0.10) : fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? accentColor.opacity(0.75) : outlineColor, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            trailing()
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
    }

    private var standardAPIFields: some View {
        Group {
            labeledInput("API Key") {
                HStack(spacing: 6) {
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
                    .buttonStyle(SettingsPillButtonStyle(
                        isDarkMode: settings.isDarkMode,
                        tone: .neutral,
                        isSelected: false,
                        compact: true
                    ))
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Advanced JSON")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Text("Paste a full request definition. Prompt presets only apply when the body includes the prompt placeholders.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(secondaryTextColor)
            }

            HStack(spacing: 6) {
                Button("Use Example") {
                    settings.aiAPIAdvancedJSONConfiguration = SettingsManager.defaultAdvancedAPIJSONConfiguration
                    resetAIDiagnostics()
                }
                .buttonStyle(SettingsPillButtonStyle(
                    isDarkMode: settings.isDarkMode,
                    tone: .accent,
                    isSelected: false
                ))

                Button("Format JSON") {
                    formatAdvancedJSONConfiguration()
                }
                .buttonStyle(SettingsPillButtonStyle(
                    isDarkMode: settings.isDarkMode,
                    tone: .neutral,
                    isSelected: false
                ))
            }

            TextEditor(text: Binding(
                get: { settings.aiAPIAdvancedJSONConfiguration },
                set: { settings.aiAPIAdvancedJSONConfiguration = $0 }
            ))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(primaryTextColor)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 220, maxHeight: 220)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
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

    private var deletedNotesSettings: some View {
        VStack(spacing: 8) {
            settingsCard {
                sectionHeader(
                    "Deleted Notes",
                    subtitle: "Recovered notes return to your library. Unrecovered notes are permanently removed after 30 days."
                )

                if store.deletedNotes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 30))
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
                        .padding(.vertical, 16)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(store.deletedNotes) { note in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(primaryTextColor)

                                    Text("Deleted \(note.deletedAt, style: .relative) ago")
                                        .font(.system(size: 12))
                                        .foregroundStyle(secondaryTextColor)
                                }

                                Spacer()

                                Button("Recover") {
                                    store.recoverNote(note)
                                }
                                .buttonStyle(SettingsPillButtonStyle(
                                    isDarkMode: settings.isDarkMode,
                                    tone: .accent,
                                    isSelected: false
                                ))
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(fieldFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(outlineColor, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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

    private var accentColor: Color {
        settings.isDarkMode
        ? Color(red: 0.89, green: 0.49, blue: 0.18)
        : Color(red: 0.90, green: 0.50, blue: 0.16)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(secondaryTextColor)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(primaryTextColor)
    }

    private func labeledInput<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(title)
            content()
        }
    }

    private func textInput(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )
    }

    private func secureInput(placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
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
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(primaryTextColor)

            Button(action: action) {
                HStack(spacing: 4) {
                    if isActionInProgress {
                        ProgressView()
                            .controlSize(.small)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    private func fieldMenuLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(primaryTextColor.opacity(0.96))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(settings.isDarkMode ? .white.opacity(0.08) : .white.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(outlineColor.opacity(1.15), lineWidth: 1)
        )
    }

    private func capsuleMenuLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(primaryTextColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(fieldFill)
        )
        .overlay(
            Capsule()
                .stroke(outlineColor, lineWidth: 1)
        )
        .contentShape(Capsule())
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
        .buttonStyle(SettingsPillButtonStyle(
            isDarkMode: settings.isDarkMode,
            tone: .accent,
            isSelected: isSelected
        ))
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
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(fieldFill.opacity(settings.isDarkMode ? 1 : 0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(outlineColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func choiceGroup<Value: Hashable>(
        title: String,
        subtitle: String,
        selection: Binding<Value>,
        options: [(String, Value)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(secondaryTextColor)

            choiceStrip(selection: selection, options: options)
        }
    }

    private func booleanChoiceGroup(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        choiceGroup(
            title: title,
            subtitle: subtitle,
            selection: isOn,
            options: [("Off", false), ("On", true)]
        )
    }

    private func choiceStrip<Value: Hashable>(
        selection: Binding<Value>,
        options: [(String, Value)]
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
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
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = selection.wrappedValue == option.1
                Button(option.0) {
                    selection.wrappedValue = option.1
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : primaryTextColor.opacity(0.88))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 30)
                .background(
                    segmentBackground(
                        isSelected: isSelected,
                        index: index,
                        count: options.count
                    )
                )
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(fieldFill)
        )
        .overlay(
            Capsule()
                .stroke(outlineColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func segmentBackground(isSelected: Bool, index: Int, count: Int) -> some View {
        if isSelected {
            UnevenRoundedRectangle(
                topLeadingRadius: index == 0 ? 999 : 6,
                bottomLeadingRadius: index == 0 ? 999 : 6,
                bottomTrailingRadius: index == count - 1 ? 999 : 6,
                topTrailingRadius: index == count - 1 ? 999 : 6,
                style: .continuous
            )
            .fill(accentColor)
        } else {
            Color.clear
        }
    }

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
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .success:
            healthStatusIcon(for: resolvedStatus)
        case .failure:
            Button {
                diagnoseStatus = "Failed"
                diagnoseResult = resolvedStatus.message ?? "The saved model health check failed."
                presentDiagnosticsPopup(
                    title: title,
                    subtitle: subtitle
                )
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
        case .idle:
            return nil
        case .testing:
            return "Testing..."
        case .success:
            return nil
        case .failure:
            return nil
        }
    }

    private func savedHealthStatusColor(for status: SavedModelHealthStatus?) -> Color {
        guard let status else { return secondaryTextColor }
        switch status.state {
        case .idle, .testing:
            return secondaryTextColor
        case .success:
            return Color.green.opacity(settings.isDarkMode ? 0.9 : 0.78)
        case .failure:
            return Color.red.opacity(settings.isDarkMode ? 0.9 : 0.78)
        }
    }

    private func apiHealthKey(for profile: AIAPIProfile) -> String {
        "api:\(profile.id)"
    }

    private func localHealthKey(for modelName: String) -> String {
        "local:\(modelName)"
    }

    private func savedProfileModelName(for profile: AIAPIProfile) -> String {
        let trimmedModel = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            return trimmedModel
        }
        if profile.requestStyle == .json {
            return extractedModelName(fromAdvancedJSONConfiguration: profile.advancedJSONConfiguration) ?? "JSON template"
        }
        return "Model not set"
    }

    private func savedProfileEndpointLabel(for profile: AIAPIProfile) -> String {
        let trimmedEndpoint = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: trimmedEndpoint)?.host, !host.isEmpty {
            return host
        }
        return trimmedEndpoint.isEmpty ? "Endpoint not set" : trimmedEndpoint
    }

    private func savedProfileEndpointLabel(for endpoint: String) -> String {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: trimmedEndpoint)?.host, !host.isEmpty {
            return host
        }
        return trimmedEndpoint.isEmpty ? "Endpoint not set" : trimmedEndpoint
    }

    private func extractedModelName(fromAdvancedJSONConfiguration rawConfiguration: String) -> String? {
        let trimmed = rawConfiguration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any],
              let body = json["body"] as? [String: Any],
              let model = body["model"] as? String else {
            return nil
        }
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func closeSettings() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var aiDiagnosticsButtonTitle: String {
        settings.aiModeEnum == .local ? "Test Local Server" : "Test API Connection"
    }

    private var diagnosticsButton: some View {
        Button(action: runLocalDiagnosticsFromHeader) {
            HStack(spacing: 4) {
                if isDiagnosing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isDiagnosing ? "Testing" : "Test")
            }
        }
        .buttonStyle(SettingsPillButtonStyle(
            isDarkMode: settings.isDarkMode,
            tone: .accent,
            isSelected: false,
            compact: true
        ))
        .disabled(isDiagnosing)
    }

    private func runActiveConfigurationTest(autoSaveAPIProfileOnSuccess: Bool) {
        isDiagnosing = true
        diagnoseResult = ""
        diagnoseStatus = "Connecting..."

        AIService.shared.diagnose(
            settings: settings,
            onStatus: { status in
                DispatchQueue.main.async {
                    diagnoseStatus = status
                }
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
        presentDiagnosticsPopup(
            title: aiDiagnosticsButtonTitle,
            subtitle: diagnosticsSubtitleText
        )
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
        if !trimmedName.isEmpty {
            return true
        }
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
        if settings.aiSelectedAPIProfile == nil {
            syncAPIProfileDraft()
        }
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

                runSavedProfilesHealthTest(
                    localModels: localModels,
                    profiles: profiles,
                    index: index + 1,
                    reports: updatedReports
                )
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

            runSavedProfilesHealthTest(
                localModels: localModels,
                profiles: profiles,
                index: index + 1,
                reports: updatedReports
            )
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

                Button("Close", action: onClose)
                    .buttonStyle(SettingsPillButtonStyle(
                        isDarkMode: isDarkMode,
                        tone: .neutral,
                        isSelected: false,
                        compact: true
                    ))
            }

            HStack(spacing: 6) {
                if isDiagnosing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isDiagnosing ? "Testing active AI configuration..." : (status.isEmpty ? "Idle" : status))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            ScrollView {
                Text(displayedText)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(primaryTextColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(width: 460, height: 220)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(outlineColor, lineWidth: 1)
            )

            HStack(spacing: 6) {
                Button("Copy Result", action: onCopy)
                    .buttonStyle(SettingsPillButtonStyle(
                        isDarkMode: isDarkMode,
                        tone: .accent,
                        isSelected: false
                    ))

                Spacer()
            }
        }
        .padding(14)
        .frame(minWidth: 500, minHeight: 330)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isDarkMode ? Color(white: 0.12) : Color(white: 0.98))
        )
    }
}

private struct SettingsPillButtonStyle: ButtonStyle {
    enum Tone {
        case neutral
        case accent
        case destructive
    }

    let isDarkMode: Bool
    let tone: Tone
    let isSelected: Bool
    var compact: Bool = false

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
            .frame(minHeight: compact ? 0 : 29)
            .background(
                Capsule()
                    .fill(backgroundColor(configuration: configuration))
            )
            .overlay(
                Capsule()
                    .stroke(strokeColor(configuration: configuration), lineWidth: 1)
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        let base: Color
        switch tone {
        case .neutral:
            base = neutralFill
        case .accent:
            base = isSelected ? accentFill : neutralFill
        case .destructive:
            base = destructiveFill
        }
        return configuration.isPressed ? base.opacity(0.85) : base
    }

    private func strokeColor(configuration: Configuration) -> Color {
        let base: Color
        switch tone {
        case .neutral:
            base = activeStroke
        case .accent:
            base = isSelected ? accentFill.opacity(0.92) : activeStroke
        case .destructive:
            base = Color.red.opacity(isDarkMode ? 0.28 : 0.22)
        }
        return configuration.isPressed ? base.opacity(0.86) : base
    }

    private func foregroundColor(configuration: Configuration) -> Color {
        let base: Color
        switch tone {
        case .accent where isSelected:
            base = .white
        case .destructive:
            base = isDarkMode ? .white.opacity(0.92) : .red.opacity(0.8)
        default:
            base = isDarkMode ? .white.opacity(0.92) : .black.opacity(0.78)
        }
        return configuration.isPressed ? base.opacity(0.88) : base
    }
}
