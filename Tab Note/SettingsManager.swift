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
    var aiEndpoint: String {
        get { defaults.string(forKey: "aiEndpoint") ?? "http://localhost:11434" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiEndpoint") }
    }
    var aiApiKey: String {
        get { defaults.string(forKey: "aiApiKey") ?? "" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiApiKey") }
    }
    var aiModel: String {
        get { defaults.string(forKey: "aiModel") ?? "" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiModel") }
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

    private init() {}

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

    static func makeAIPromptSummaryChip(selection: PromptInjectionSelection) -> String {
        shared.promptInjectionConfiguration.summaryChip(for: selection)
    }

    func resetAIPromptSelection() {
        aiPromptSelection = promptInjectionConfiguration.defaultSelection
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
