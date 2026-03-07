//
//  SettingsManager.swift
//  Tab Note
//
//  Created by Kien Tran on 2026-03-03.
//

import Foundation
import Combine
import AppKit
import ServiceManagement

enum PositionMode: String, CaseIterable {
    case cursor = "cursor"
    case topRight = "topRight"

    var displayName: String {
        switch self {
        case .cursor: return "At Cursor Position"
        case .topRight: return "Top Right Corner"
        }
    }
}

enum FontChoice: String, CaseIterable {
    case sansSerif = "sansSerif"
    case serif = "serif"
    case monospace = "monospace"

    var displayName: String {
        switch self {
        case .sansSerif: return "Sans Serif"
        case .serif: return "Serif"
        case .monospace: return "Monospace"
        }
    }

    var nsFont: NSFont {
        switch self {
        case .sansSerif:
            return NSFont.systemFont(ofSize: 14, weight: .regular)
        case .serif:
            return NSFont(name: "Georgia", size: 14) ?? NSFont.systemFont(ofSize: 14)
        case .monospace:
            return NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        }
    }
}

enum AIMode: String, CaseIterable {
    case local = "local"
    case api = "api"

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .api: return "API"
        }
    }
}

struct AIAPIProfile: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var endpoint: String
    var apiKey: String
    var headerName: String
    var model: String

    init(
        id: String = UUID().uuidString,
        name: String,
        endpoint: String,
        apiKey: String,
        headerName: String,
        model: String
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.headerName = headerName
        self.model = model
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    static let hotkeyKeyNames: [Int: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9", 29: "0", 49: "Space", 36: "Return"
    ]

    let objectWillChange = ObservableObjectPublisher()
    private let defaults = UserDefaults.standard
    let promptInjectionConfiguration = PromptInjectionConfigurationStore.shared.configuration
    private let legacyAIEndpointKey = "aiEndpoint"
    private let legacyAIModelKey = "aiModel"
    private let aiLocalEndpointKey = "aiLocalEndpoint"
    private let aiLocalModelKey = "aiLocalModel"
    private let aiAPIEndpointKey = "aiAPIEndpoint"
    private let aiAPIModelKey = "aiAPIModel"
    private let aiAPISavedProfilesKey = "aiAPISavedProfiles"
    private let aiAPISelectedProfileIDKey = "aiAPISelectedProfileID"
    private let settingsPanelWidthKey = "settingsPanelWidth"
    private let settingsPanelHeightKey = "settingsPanelHeight"

    var positionMode: String {
        get { defaults.string(forKey: "positionMode") ?? PositionMode.cursor.rawValue }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "positionMode") }
    }
    var selectedFont: String {
        get { defaults.string(forKey: "selectedFont") ?? FontChoice.sansSerif.rawValue }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "selectedFont") }
    }
    var aiMode: String {
        get { defaults.string(forKey: "aiMode") ?? AIMode.local.rawValue }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiMode") }
    }
    var aiLocalEndpoint: String {
        get { defaults.string(forKey: aiLocalEndpointKey) ?? "http://localhost:11434" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: aiLocalEndpointKey) }
    }
    var aiLocalModel: String {
        get { defaults.string(forKey: aiLocalModelKey) ?? "" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: aiLocalModelKey) }
    }
    var aiAPIEndpoint: String {
        get { defaults.string(forKey: aiAPIEndpointKey) ?? "https://api.openai.com/v1" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: aiAPIEndpointKey) }
    }
    var aiApiKey: String {
        get { defaults.string(forKey: "aiApiKey") ?? "" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiApiKey") }
    }
    var aiAPIHeaderName: String {
        get { defaults.string(forKey: "aiAPIHeaderName") ?? "Authorization" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiAPIHeaderName") }
    }
    var aiAPIModel: String {
        get { defaults.string(forKey: aiAPIModelKey) ?? "" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: aiAPIModelKey) }
    }
    var aiAPISavedProfiles: [AIAPIProfile] {
        get {
            guard let data = defaults.data(forKey: aiAPISavedProfilesKey),
                  let profiles = try? JSONDecoder().decode([AIAPIProfile].self, from: data) else {
                return []
            }
            return profiles
        }
        set {
            objectWillChange.send()
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: aiAPISavedProfilesKey)
            } else {
                defaults.removeObject(forKey: aiAPISavedProfilesKey)
            }
        }
    }
    var aiAPISelectedProfileID: String? {
        get { defaults.string(forKey: aiAPISelectedProfileIDKey) }
        set {
            objectWillChange.send()
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: aiAPISelectedProfileIDKey)
            } else {
                defaults.removeObject(forKey: aiAPISelectedProfileIDKey)
            }
        }
    }
    var settingsPanelSize: NSSize {
        get {
            let storedWidth = defaults.object(forKey: settingsPanelWidthKey) as? Double ?? 620
            let storedHeight = defaults.object(forKey: settingsPanelHeightKey) as? Double ?? 610
            return NSSize(width: max(560, storedWidth), height: max(520, storedHeight))
        }
        set {
            let width = max(560, newValue.width)
            let height = max(520, newValue.height)
            defaults.set(width, forKey: settingsPanelWidthKey)
            defaults.set(height, forKey: settingsPanelHeightKey)
        }
    }
    var aiResponseLengthID: String {
        get { promptInjectionConfiguration.normalizedResponseLengthID(defaults.string(forKey: "aiResponseLengthPreset")) }
        set {
            objectWillChange.send()
            defaults.set(promptInjectionConfiguration.normalizedResponseLengthID(newValue), forKey: "aiResponseLengthPreset")
        }
    }
    var aiResponseModeID: String? {
        get { promptInjectionConfiguration.normalizedOptionalSelectionID(defaults.string(forKey: "aiResponseModePreset"), dimension: .responseMode) }
        set {
            objectWillChange.send()
            if let normalized = promptInjectionConfiguration.normalizedOptionalSelectionID(newValue, dimension: .responseMode) {
                defaults.set(normalized, forKey: "aiResponseModePreset")
            } else {
                defaults.removeObject(forKey: "aiResponseModePreset")
            }
        }
    }
    var aiExpertModeID: String? {
        get { promptInjectionConfiguration.normalizedOptionalSelectionID(defaults.string(forKey: "aiExpertDisciplinePreset"), dimension: .expertMode) }
        set {
            objectWillChange.send()
            if let normalized = promptInjectionConfiguration.normalizedOptionalSelectionID(newValue, dimension: .expertMode) {
                defaults.set(normalized, forKey: "aiExpertDisciplinePreset")
            } else {
                defaults.removeObject(forKey: "aiExpertDisciplinePreset")
            }
        }
    }
    var aiVoiceModeID: String? {
        get { promptInjectionConfiguration.normalizedOptionalSelectionID(defaults.string(forKey: "aiVoiceFigurePreset"), dimension: .voiceMode) }
        set {
            objectWillChange.send()
            if let normalized = promptInjectionConfiguration.normalizedOptionalSelectionID(newValue, dimension: .voiceMode) {
                defaults.set(normalized, forKey: "aiVoiceFigurePreset")
            } else {
                defaults.removeObject(forKey: "aiVoiceFigurePreset")
            }
        }
    }
    var hotkeyKeyCode: Int {
        get { defaults.object(forKey: "hotkeyKeyCode") as? Int ?? 1 }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "hotkeyKeyCode"); AppDelegate.shared?.registerGlobalHotKey() }
    }
    // Carbon modifier flags: cmdKey=0x100, shiftKey=0x200, optionKey=0x800, controlKey=0x1000
    var hotkeyModifiers: Int {
        get { defaults.object(forKey: "hotkeyModifiers") as? Int ?? (0x0100 | 0x0200) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "hotkeyModifiers"); AppDelegate.shared?.registerGlobalHotKey() }
    }
    var isDarkMode: Bool {
        get { defaults.object(forKey: "isDarkMode") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "isDarkMode") }
    }
    var alwaysOnTop: Bool {
        get { defaults.object(forKey: "alwaysOnTop") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "alwaysOnTop") }
    }
    var appThemeHex: String {
        get { defaults.object(forKey: "appThemeHex") as? String ?? "defaultOrange" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "appThemeHex") }
    }
    var maxTabRows: Int {
        get { defaults.object(forKey: "maxTabRows") as? Int ?? 2 }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "maxTabRows") }
    }
    var autoCheckUpdates: Bool {
        get { defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "autoCheckUpdates") }
    }

    private init() {
        migrateLegacyAISettingsIfNeeded()
    }

    var hotkeyDisplayLabel: String {
        var parts: [String] = []
        let m = hotkeyModifiers
        if m & 0x0100 != 0 { parts.append("⌘") }
        if m & 0x0200 != 0 { parts.append("⇧") }
        if m & 0x0800 != 0 { parts.append("⌥") }
        if m & 0x1000 != 0 { parts.append("⌃") }
        let key = SettingsManager.hotkeyKeyNames[hotkeyKeyCode] ?? "?"
        return parts.joined() + key
    }

    var positionModeEnum: PositionMode {
        get { PositionMode(rawValue: positionMode) ?? .cursor }
        set { positionMode = newValue.rawValue }
    }

    var selectedFontEnum: FontChoice {
        get { FontChoice(rawValue: selectedFont) ?? .sansSerif }
        set { selectedFont = newValue.rawValue }
    }

    var aiModeEnum: AIMode {
        get { AIMode(rawValue: aiMode) ?? .local }
        set { aiMode = newValue.rawValue }
    }

    var currentAIEndpoint: String {
        switch aiModeEnum {
        case .local:
            return aiLocalEndpoint
        case .api:
            return aiAPIEndpoint
        }
    }

    var currentAIModel: String {
        switch aiModeEnum {
        case .local:
            return aiLocalModel
        case .api:
            return aiAPIModel
        }
    }

    var aiPromptSelection: PromptInjectionSelection {
        get {
            promptInjectionConfiguration.normalized(
                PromptInjectionSelection(
                    responseLengthID: aiResponseLengthID,
                    responseModeIDs: Set(aiResponseModeID.map { [$0] } ?? []),
                    expertModeIDs: Set(aiExpertModeID.map { [$0] } ?? []),
                    voiceModeID: aiVoiceModeID
                )
            )
        }
        set {
            let normalized = promptInjectionConfiguration.normalized(newValue)
            aiResponseLengthID = normalized.responseLengthID
            aiResponseModeID = normalized.responseModeIDs.first
            aiExpertModeID = normalized.expertModeIDs.first
            aiVoiceModeID = normalized.voiceModeID
        }
    }

    var aiResponseLengthOption: PromptInjectionOption {
        promptInjectionConfiguration.responseLengthOption(id: aiResponseLengthID)
            ?? promptInjectionConfiguration.responseLengthOptions.first!
    }

    var aiResponseModeOption: PromptInjectionOption? {
        promptInjectionConfiguration.responseModeOption(id: aiResponseModeID)
    }

    var aiExpertModeOption: PromptInjectionOption? {
        promptInjectionConfiguration.expertModeOption(id: aiExpertModeID)
    }

    var aiVoiceModeOption: PromptInjectionOption? {
        promptInjectionConfiguration.voiceModeOption(id: aiVoiceModeID)
    }

    var aiCustomInstruction: String {
        promptInjectionConfiguration.instruction(for: aiPromptSelection)
    }

    var aiPromptSummaryChip: String {
        SettingsManager.makeAIPromptSummaryChip(selection: aiPromptSelection)
    }

    var aiSelectedAPIProfile: AIAPIProfile? {
        guard let aiAPISelectedProfileID else { return nil }
        return aiAPISavedProfiles.first { $0.id == aiAPISelectedProfileID }
    }

    static func makeAIPromptSummaryChip(selection: PromptInjectionSelection) -> String {
        shared.promptInjectionConfiguration.summaryChip(for: selection)
    }

    func resetAIPromptSelection() {
        aiPromptSelection = promptInjectionConfiguration.defaultSelection
    }

    func suggestedAPIProfileName() -> String {
        let trimmedModel = aiAPIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            return trimmedModel
        }
        if let host = URL(string: aiAPIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host,
           !host.isEmpty {
            return host
        }
        return "API Setup \(aiAPISavedProfiles.count + 1)"
    }

    func saveCurrentAPIProfile(named preferredName: String?) -> AIAPIProfile {
        let profile = AIAPIProfile(
            name: normalizedAPIProfileName(preferredName),
            endpoint: aiAPIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            headerName: normalizedAPIHeaderName(aiAPIHeaderName),
            model: aiAPIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        var profiles = aiAPISavedProfiles
        profiles.append(profile)
        aiAPISavedProfiles = profiles
        aiAPISelectedProfileID = profile.id
        return profile
    }

    @discardableResult
    func applyAPIProfile(id: String) -> Bool {
        guard let profile = aiAPISavedProfiles.first(where: { $0.id == id }) else { return false }
        aiAPISelectedProfileID = profile.id
        aiAPIEndpoint = profile.endpoint
        aiApiKey = profile.apiKey
        aiAPIHeaderName = profile.headerName
        aiAPIModel = profile.model
        return true
    }

    @discardableResult
    func updateSelectedAPIProfile(named preferredName: String?) -> AIAPIProfile? {
        guard let selectedID = aiAPISelectedProfileID,
              let index = aiAPISavedProfiles.firstIndex(where: { $0.id == selectedID }) else {
            return nil
        }

        var profiles = aiAPISavedProfiles
        profiles[index] = AIAPIProfile(
            id: selectedID,
            name: normalizedAPIProfileName(preferredName),
            endpoint: aiAPIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            headerName: normalizedAPIHeaderName(aiAPIHeaderName),
            model: aiAPIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        aiAPISavedProfiles = profiles
        aiAPISelectedProfileID = selectedID
        return profiles[index]
    }

    @discardableResult
    func deleteAPIProfile(id: String) -> AIAPIProfile? {
        var profiles = aiAPISavedProfiles
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = profiles.remove(at: index)
        aiAPISavedProfiles = profiles
        if aiAPISelectedProfileID == id {
            aiAPISelectedProfileID = nil
        }
        return removed
    }

    private func migrateLegacyAISettingsIfNeeded() {
        let legacyEndpoint = defaults.string(forKey: legacyAIEndpointKey)
        let legacyModel = defaults.string(forKey: legacyAIModelKey)
        let legacyMode = AIMode(rawValue: defaults.string(forKey: "aiMode") ?? "") ?? .local

        if defaults.string(forKey: aiLocalEndpointKey) == nil {
            defaults.set(legacyMode == .local ? (legacyEndpoint ?? "http://localhost:11434") : "http://localhost:11434", forKey: aiLocalEndpointKey)
        }
        if defaults.string(forKey: aiAPIEndpointKey) == nil {
            defaults.set(legacyMode == .api ? (legacyEndpoint ?? "https://api.openai.com/v1") : "https://api.openai.com/v1", forKey: aiAPIEndpointKey)
        }
        if defaults.string(forKey: aiLocalModelKey) == nil {
            defaults.set(legacyMode == .local ? (legacyModel ?? "") : "", forKey: aiLocalModelKey)
        }
        if defaults.string(forKey: aiAPIModelKey) == nil {
            defaults.set(legacyMode == .api ? (legacyModel ?? "") : "", forKey: aiAPIModelKey)
        }
    }

    private func normalizedAPIProfileName(_ preferredName: String?) -> String {
        let trimmed = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? suggestedAPIProfileName() : trimmed
    }

    private func normalizedAPIHeaderName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Authorization" : trimmed
    }

    var launchAtLogin: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                objectWillChange.send()
            } catch {
                print("Failed to set launch at login: \(error)")
            }
        }
    }
}
