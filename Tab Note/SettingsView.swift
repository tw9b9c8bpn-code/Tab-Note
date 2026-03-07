//
//  SettingsView.swift
//  Tab Note
//
//  Created by Kien Tran on 2026-03-03.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var store: NotesStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Tab bar for settings sections
            HStack(spacing: 0) {
                settingsTab("General", index: 0)
                settingsTab("Deleted Notes", index: 1)
                settingsTab("AI", index: 2)
            }
            .padding(.horizontal, 20)

            Divider()
                .padding(.horizontal, 20)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case 0:
                        generalSettings
                    case 1:
                        deletedNotesSettings
                    case 2:
                        aiSettings
                    default:
                        EmptyView()
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 450)
        .background(settings.isDarkMode ? Color(white: 0.15) : Color(white: 0.96))
    }

    // MARK: - General Settings

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hotkey
            VStack(alignment: .leading, spacing: 8) {
                Text("Global Hotkey")
                    .font(.system(size: 13, weight: .semibold))
                Text("Shortcut to show / hide Tab Note from anywhere.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                // Modifier toggles
                HStack(spacing: 8) {
                    modifierToggle(label: "⌘ Cmd",   flag: 0x0100)
                    modifierToggle(label: "⇧ Shift",  flag: 0x0200)
                    modifierToggle(label: "⌥ Option", flag: 0x0800)
                    modifierToggle(label: "⌃ Ctrl",   flag: 0x1000)
                }

                // Key picker
                HStack(spacing: 8) {
                    Text("Key:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { settings.hotkeyKeyCode },
                        set: { settings.hotkeyKeyCode = $0 }
                    )) {
                        ForEach(hotkeyKeys, id: \.0) { code, label in
                            Text(label).tag(code)
                        }
                    }
                    .frame(width: 80)
                    Text("Current: \(settings.hotkeyDisplayLabel)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Position mode
            VStack(alignment: .leading, spacing: 6) {
                Text("Window Position")
                    .font(.system(size: 13, weight: .semibold))
                Picker("", selection: Binding(
                    get: { settings.positionMode },
                    set: { settings.positionMode = $0 }
                )) {
                    ForEach(PositionMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }

            Divider()

            // Max tab rows
            VStack(alignment: .leading, spacing: 6) {
                Text("Max Tab Rows")
                    .font(.system(size: 13, weight: .semibold))
                Picker("", selection: Binding(
                    get: { settings.maxTabRows },
                    set: { settings.maxTabRows = $0 }
                )) {
                    Text("2 rows").tag(2)
                    Text("3 rows").tag(3)
                    Text("4 rows").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Text("Controls how many rows of tabs are shown before overflow.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Launch at login
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                .font(.system(size: 13, weight: .semibold))
                Text("Automatically start Tab Note when you log in.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Auto Update
            VStack(alignment: .leading, spacing: 8) {
                Text("Updates")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 10) {
                    Button(action: { AppUpdater.shared.checkForUpdates() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 11))
                            Text("Check for Updates")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    Toggle("Auto-check on launch", isOn: Binding(
                        get: { settings.autoCheckUpdates },
                        set: { settings.autoCheckUpdates = $0 }
                    ))
                    .font(.system(size: 12))
                    .toggleStyle(.checkbox)
                }
                Text("Tab Note will check for new versions from the update feed.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Deleted Notes

    private var deletedNotesSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deleted Notes")
                .font(.system(size: 13, weight: .semibold))
            Text("Notes are permanently deleted after 30 days.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if store.deletedNotes.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No deleted notes")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                ForEach(store.deletedNotes) { note in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .font(.system(size: 13, weight: .medium))
                            Text("Deleted \(note.deletedAt, style: .relative) ago")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Recover") {
                            store.recoverNote(note)
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    // MARK: - AI Settings

    @State private var isDiagnosing = false
    @State private var diagnoseResult = ""
    @State private var diagnoseStatus = ""
    @State private var availableLocalModels: [String] = []
    @State private var isLoadingLocalModels = false
    @State private var localModelsStatus = ""
    @State private var showsAPIKey = false

    private var aiSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Picker("", selection: Binding(
                get: { settings.aiMode },
                set: {
                    settings.aiMode = $0
                    resetAIDiagnostics()
                    if AIMode(rawValue: $0) == .local {
                        refreshLocalModels()
                    }
                }
            )) {
                ForEach(AIMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }

            activeAIProviderCard

            Text("AI will add content to the end of the current note when triggered.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Divider()

            aiDiagnosticsSection
        }
        .onAppear {
            if settings.aiModeEnum == .local && availableLocalModels.isEmpty {
                refreshLocalModels()
            }
        }
    }

    private var activeAIProviderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.aiModeEnum.displayName)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            if settings.aiModeEnum == .local {
                VStack(alignment: .leading, spacing: 8) {
                    aiFieldLabel("Local Endpoint")
                    TextField("http://localhost:11434", text: Binding(
                        get: { settings.aiLocalEndpoint },
                        set: { settings.aiLocalEndpoint = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                    aiFieldLabel("Model Name")
                    TextField("e.g. llama3", text: Binding(
                        get: { settings.aiLocalModel },
                        set: { settings.aiLocalModel = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                    HStack(spacing: 8) {
                        Button(action: refreshLocalModels) {
                            HStack(spacing: 5) {
                                if isLoadingLocalModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                Text(isLoadingLocalModels ? "Loading..." : "Refresh Local Models")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingLocalModels)

                        if !availableLocalModels.isEmpty {
                            Menu("Available Models") {
                                ForEach(availableLocalModels, id: \.self) { modelName in
                                    Button(modelName) {
                                        settings.aiLocalModel = modelName
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }

                    if !localModelsStatus.isEmpty {
                        Text(localModelsStatus)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    aiFieldLabel("API Key")
                    HStack(spacing: 8) {
                        Group {
                            if showsAPIKey {
                                TextField("Enter API key", text: Binding(
                                    get: { settings.aiApiKey },
                                    set: { settings.aiApiKey = $0 }
                                ))
                            } else {
                                SecureField("Enter API key", text: Binding(
                                    get: { settings.aiApiKey },
                                    set: { settings.aiApiKey = $0 }
                                ))
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                        Button {
                            showsAPIKey.toggle()
                        } label: {
                            Image(systemName: showsAPIKey ? "eye.slash" : "eye")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("If the error says the key ends with `/v1`, the API Key field currently contains your endpoint instead of the real secret key.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    aiFieldLabel("API Header")
                    TextField("Authorization", text: Binding(
                        get: { settings.aiAPIHeaderName },
                        set: { settings.aiAPIHeaderName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                    aiFieldLabel("API Endpoint")
                    TextField("https://api.openai.com/v1", text: Binding(
                        get: { settings.aiAPIEndpoint },
                        set: { settings.aiAPIEndpoint = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                    aiFieldLabel("Model Name")
                    TextField("e.g. gpt-4", text: Binding(
                        get: { settings.aiAPIModel },
                        set: { settings.aiAPIModel = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                    Text("Supports OpenAI-style `/v1` bases and Anthropic-style `/anthropic` bases.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(settings.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(settings.isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var aiDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics")
                .font(.system(size: 13, weight: .semibold))
            Text(settings.aiModeEnum == .local
                 ? "Checks the local endpoint and lists installed models."
                 : "Checks the API endpoint with the configured header, endpoint, and request protocol.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack {
                Button(action: {
                    runDiagnose()
                }) {
                    HStack(spacing: 4) {
                        if isDiagnosing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 12))
                        }
                        Text(isDiagnosing ? "Testing..." : aiDiagnosticsButtonTitle)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isDiagnosing)

                if !diagnoseStatus.isEmpty {
                    Text(diagnoseStatus)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            if !diagnoseResult.isEmpty {
                Text(diagnoseResult)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(settings.isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )
            }
        }
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
                        diagnoseStatus = "✅ Connected"
                    case .failure(let error):
                        diagnoseResult = "❌ \(error.localizedDescription)"
                        diagnoseStatus = "Failed"
                    }
                }
            }
        )
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

    private var aiDiagnosticsButtonTitle: String {
        settings.aiModeEnum == .local ? "Test Local Server" : "Test API Connection"
    }

    private func resetAIDiagnostics() {
        isDiagnosing = false
        diagnoseResult = ""
        diagnoseStatus = ""
    }

    // MARK: - Helper

    private func settingsTab(_ title: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            Text(title)
                .font(.system(size: 12, weight: selectedTab == index ? .semibold : .regular))
                .foregroundColor(selectedTab == index
                                 ? (settings.isDarkMode ? .white : .black)
                                 : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selectedTab == index
                    ? (settings.isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                    : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func modifierToggle(label: String, flag: Int) -> some View {
        let isOn = Binding<Bool>(
            get: { (settings.hotkeyModifiers & flag) != 0 },
            set: { newValue in
                if newValue {
                    settings.hotkeyModifiers |= flag
                } else {
                    settings.hotkeyModifiers &= ~flag
                }
            }
        )
        return Toggle(label, isOn: isOn)
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
    }

    private func aiFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
    }

    private let hotkeyKeys: [(Int, String)] = SettingsManager.hotkeyKeyNames
        .map { ($0.key, $0.value) }
        .sorted { $0.1 < $1.1 }
}
