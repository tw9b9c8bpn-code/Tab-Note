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

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var store: NotesStore
    @Environment(\.dismiss) private var dismiss

    let onClose: (() -> Void)?

    @State private var selectedTab: SettingsTab = .general

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
        }
        .frame(minWidth: 560, minHeight: 520)
        .sheet(isPresented: $showsDiagnosticsPopup) {
            AIDiagnosticsPopup(
                title: aiDiagnosticsButtonTitle,
                subtitle: diagnosticsSubtitleText,
                status: diagnoseStatus,
                result: diagnoseResult,
                isDiagnosing: isDiagnosing,
                isDarkMode: settings.isDarkMode,
                onCopy: copyDiagnosticsToPasteboard,
                onClose: { showsDiagnosticsPopup = false }
            )
        }
        .onAppear {
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
            ForEach([SettingsTab.general, .ai, .deletedNotes]) { tab in
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                }
                .buttonStyle(SettingsPillButtonStyle(
                    isDarkMode: settings.isDarkMode,
                    tone: .accent,
                    isSelected: selectedTab == tab
                ))
            }
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
                            capsuleMenuLabel("Key: \(SettingsManager.hotkeyKeyNames[settings.hotkeyKeyCode] ?? "?")")
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
                    choiceStrip(
                        selection: Binding(
                            get: { settings.aiModeEnum },
                            set: { settings.aiModeEnum = $0 }
                        ),
                        options: AIMode.allCases.map { ($0.displayName, $0) }
                    )
                    Spacer()
                }
            }

            if settings.aiModeEnum == .local {
                localAISettingsCard
            } else {
                apiSettingsCard
            }
        }
    }

    private var localAISettingsCard: some View {
        settingsCard {
            HStack(alignment: .top, spacing: 8) {
                sectionHeader(
                    "Local Connection",
                    subtitle: "Point Tab Note at your local endpoint and choose an installed model."
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

            labeledInput("Installed Models") {
                HStack(spacing: 6) {
                    Menu {
                        if availableLocalModels.isEmpty {
                            Button("No models found") { }
                                .disabled(true)
                        } else {
                            ForEach(availableLocalModels, id: \.self) { modelName in
                                Button(modelName) {
                                    settings.aiLocalModel = modelName
                                }
                            }
                        }
                    } label: {
                        capsuleMenuLabel(localModelMenuTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(availableLocalModels.isEmpty)

                    Button(action: refreshLocalModels) {
                        HStack(spacing: 4) {
                            if isLoadingLocalModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text(isLoadingLocalModels ? "Refreshing..." : "Refresh")
                        }
                    }
                    .buttonStyle(SettingsPillButtonStyle(
                        isDarkMode: settings.isDarkMode,
                        tone: .neutral,
                        isSelected: false
                    ))
                    .disabled(isLoadingLocalModels)
                }
            }

            if !localModelsStatus.isEmpty {
                Text(localModelsStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryTextColor)
            }
        }
    }

    private var apiSettingsCard: some View {
        settingsCard {
            HStack(alignment: .top, spacing: 8) {
                sectionHeader(
                    "API Connection",
                    subtitle: "Switch saved setups fast and keep advanced JSON inside the same API workflow."
                )
                Spacer(minLength: 8)
                diagnosticsButton
            }

            labeledInput("Saved Configurations") {
                Menu {
                    Button("Current Unsaved") {
                        selectAPIProfile("")
                    }

                    if !settings.aiAPISavedProfiles.isEmpty {
                        Divider()
                    }

                    ForEach(settings.aiAPISavedProfiles) { profile in
                        Button(profileMenuTitle(for: profile)) {
                            selectAPIProfile(profile.id)
                        }
                    }
                } label: {
                    capsuleMenuLabel(
                        settings.aiSelectedAPIProfile.map { profileMenuTitle(for: $0) }
                        ?? "Current Unsaved"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
            }

            labeledInput("Configuration Name") {
                textInput(placeholder: "Preset name", text: $apiProfileNameDraft)
            }

            HStack(spacing: 6) {
                Button("Save Current") {
                    saveCurrentAPIProfile()
                }
                .buttonStyle(SettingsPillButtonStyle(
                    isDarkMode: settings.isDarkMode,
                    tone: .accent,
                    isSelected: false
                ))
                .disabled(!canSaveAPIProfile)

                Button("Update") {
                    updateSelectedAPIProfile()
                }
                .buttonStyle(SettingsPillButtonStyle(
                    isDarkMode: settings.isDarkMode,
                    tone: .neutral,
                    isSelected: false
                ))
                .disabled(settings.aiSelectedAPIProfile == nil)

                Button("Delete") {
                    deleteSelectedAPIProfile()
                }
                .buttonStyle(SettingsPillButtonStyle(
                    isDarkMode: settings.isDarkMode,
                    tone: .destructive,
                    isSelected: false
                ))
                .disabled(settings.aiSelectedAPIProfile == nil)
            }

            Text("Standard and JSON presets stay together in this one list and restore the full API state.")
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

    private var localModelMenuTitle: String {
        let trimmedModel = settings.aiLocalModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            return trimmedModel
        }
        return availableLocalModels.isEmpty ? "Choose Installed Model" : "Installed Models"
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
        Button(action: openDiagnosticsPopupAndRun) {
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

    private func runDiagnose() {
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
                        diagnoseResult = info
                        diagnoseStatus = "Connected"
                    case .failure(let error):
                        diagnoseResult = "X \(error.localizedDescription)"
                        diagnoseStatus = "Failed"
                    }
                }
            }
        )
    }

    private func openDiagnosticsPopupAndRun() {
        showsDiagnosticsPopup = true
        runDiagnose()
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
                    localModelsStatus = models.isEmpty
                        ? "No local models were returned by the current endpoint."
                        : "\(models.count) local model\(models.count == 1 ? "" : "s") found."
                case .failure(let error):
                    availableLocalModels = []
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
    }

    private var canSaveAPIProfile: Bool {
        let trimmedName = apiProfileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return true
        }
        switch settings.aiAPIRequestStyleEnum {
        case .standard:
            let values = [settings.aiAPIEndpoint, settings.aiAPIModel, settings.aiApiKey]
            return values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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

    private func saveCurrentAPIProfile() {
        let profile = settings.saveCurrentAPIProfile(named: apiProfileNameDraft)
        apiProfileNameDraft = profile.name
        apiProfileStatus = "Saved \(profile.name)."
        resetAIDiagnostics()
    }

    private func updateSelectedAPIProfile() {
        guard let profile = settings.updateSelectedAPIProfile(named: apiProfileNameDraft) else { return }
        apiProfileNameDraft = profile.name
        apiProfileStatus = "Updated \(profile.name)."
        resetAIDiagnostics()
    }

    private func deleteSelectedAPIProfile() {
        guard let selectedProfile = settings.aiSelectedAPIProfile,
              let removed = settings.deleteAPIProfile(id: selectedProfile.id) else { return }
        apiProfileStatus = "Deleted \(removed.name)."
        syncAPIProfileDraft()
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

    private func profileMenuTitle(for profile: AIAPIProfile) -> String {
        "\(profile.name) • \(profile.requestStyle.displayName)"
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
