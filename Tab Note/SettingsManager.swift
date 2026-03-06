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

enum AIResponseLengthPreset: String, CaseIterable {
    case xs = "XS"
    case s = "S"
    case m = "M"
    case l = "L"
    case xl = "XL"

    var displayName: String { rawValue }

    var injectionInstruction: String {
        switch self {
        case .xs: return "[IMPORTANT: Keep your response under 20 words. Be extremely brief.]"
        case .s: return "[IMPORTANT: Keep your response under 100 words. Be concise.]"
        case .m: return "[IMPORTANT: Keep your response under 300 words. Be moderately detailed.]"
        case .l: return ""
        case .xl: return "[Provide the most comprehensive and detailed response possible.]"
        }
    }
}

enum AIResponseModePreset: String, CaseIterable {
    case none = "NONE"
    case analogy = "A"
    case socratic = "S"
    case dialog = "D"
    case inversion = "I"
    case manifesto = "M"
    case rant = "R"
    case interactiveSimulation = "IS"
    case tableOfContents = "T"
    case pareto80 = "80"
    case secondOrder2O = "2O"
    case tierList = "TL"
    case firstPrinciple = "FP"

    var menuTitle: String {
        switch self {
        case .none: return "None"
        case .analogy: return "A (analogy)"
        case .socratic: return "S (socratic)"
        case .dialog: return "D (dialog)"
        case .inversion: return "I (inversion)"
        case .manifesto: return "M (manifesto)"
        case .rant: return "R (rant)"
        case .interactiveSimulation: return "IS (interactive)"
        case .tableOfContents: return "T (ToC)"
        case .pareto80: return "80 (pareto)"
        case .secondOrder2O: return "2O (secondOrder)"
        case .tierList: return "TL (tierList)"
        case .firstPrinciple: return "FP (firstPrinciple)"
        }
    }

    var injectionInstruction: String {
        switch self {
        case .none:
            return ""
        case .analogy:
            return "[Explain using analogies and metaphors to make concepts relatable.]"
        case .socratic:
            return "[Answer only with thought-provoking questions to guide understanding.]"
        case .dialog:
            return "[Present the explanation as a dialog between characters.]"
        case .inversion:
            return "[Explain by describing what NOT to do and common mistakes to avoid.]"
        case .manifesto:
            return "[Explain with the passion and conviction of a manifesto.]"
        case .rant:
            return "[Give an entertaining rant-style explanation with strong opinions.]"
        case .interactiveSimulation:
            return "[Create an interactive HTML simulation to demonstrate the concept. Include complete HTML/CSS/JS code that can run standalone.]"
        case .tableOfContents:
            return "[Explain as table of content of a Textbook]"
        case .pareto80:
            return "[Apply the 80/20 Pareto Principle: identify the critical 20% of inputs, causes, or actions that drive 80% of the results. Cut through the noise and ruthlessly focus on what actually moves the needle.]"
        case .secondOrder2O:
            return "[Use second-order thinking: go beyond the immediate first consequence. For every effect, ask 'and then what?' Reveal the downstream chain reactions, unintended outcomes, and long-term implications that most people miss.]"
        case .tierList:
            return "[Rank and categorize everything into a tier list using S (exceptional/elite), A (excellent), B (good), C (average), D (below average), and F (failing/avoid). Be decisive, opinionated, and justify each placement clearly.]"
        case .firstPrinciple:
            return "[Use first-principles thinking: strip away all assumptions, conventions, and analogies. Decompose the problem down to its most fundamental, irreducible truths. Then reason upward from those foundations to construct a fresh, clear answer from the ground up.]"
        }
    }
}

enum AIExpertDisciplinePreset: String, CaseIterable {
    case none = "NONE"
    case phy = "Phy"
    case bio = "Bio"
    case evoBio = "EvoBio"
    case eco = "Eco"
    case sys = "Sys"
    case gam = "Gam"
    case ecn = "Ecn"
    case psy = "Psy"
    case phi = "Phi"
    case lng = "Lng"
    case art = "Art"
    case eng = "Eng"
    case chm = "Chm"
    case tec = "Tec"
    case elc = "Elc"
    case acc = "Acc"
    case che = "Che"
    case nut = "Nut"
    case doc = "Doc"
    case des = "Des"
    case fen = "Fen"
    case arc = "Arc"

    var roleTitle: String {
        switch self {
        case .none: return "None"
        case .phy: return "Physicist"
        case .bio: return "Biologist"
        case .evoBio: return "Evolutionary Biologist"
        case .eco: return "Ecologist"
        case .sys: return "Systems Theorist"
        case .gam: return "Game Theorist"
        case .ecn: return "Economist"
        case .psy: return "Psychologist"
        case .phi: return "Philosopher"
        case .lng: return "Linguist"
        case .art: return "Artist"
        case .eng: return "Engineer"
        case .chm: return "Chemist"
        case .tec: return "Technologist"
        case .elc: return "Electrician"
        case .acc: return "Accountant"
        case .che: return "Chef"
        case .nut: return "Nutritionist"
        case .doc: return "Doctor"
        case .des: return "Designer"
        case .fen: return "Feng Shui Expert"
        case .arc: return "Architect"
        }
    }

    var menuTitle: String {
        self == .none ? "None" : "\(rawValue) (\(roleTitle))"
    }

    var injectionInstruction: String {
        guard self != .none else { return "" }
        return "[Act as a \(roleTitle)]"
    }
}

enum AIVoiceFigurePreset: String, CaseIterable {
    case none = "NONE"
    case aynRand = "Ayn Rand"
    case leeKuanYew = "Lee Kuan Yew"
    case eckhartTolle = "Eckhart Tolle"
    case jidduKrishnamurti = "Jiddu Krishnamurti"
    case aristotle = "Aristotle"
    case machiavelli = "Machiavelli"
    case nietzsche = "Nietzsche"
    case erichFromm = "Erich Fromm"
    case michaelGreger = "Michael Greger"
    case michaelSaylor = "Michael Saylor"
    case maxwellMaltz = "Maxwell Maltz"
    case byungChulHan = "Byung-Chul Han"
    case harryBrowne = "Harry Browne"
    case sethGodin = "Seth Godin"
    case drNicoleLePera = "Dr. Nicole LePera"
    case richardKoch = "Richard Koch"
    case jeffBezos = "Jeff Bezos"
    case sunTzu = "Sun Tzu"
    case leonardoDaVinci = "Leonardo da Vinci"
    case navalRavikant = "Naval Ravikant"

    var menuTitle: String {
        self == .none ? "None" : rawValue
    }

    var summaryLabel: String {
        guard self != .none else { return "Voice" }
        let cleaned = rawValue
            .replacingOccurrences(of: "Dr. ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.split(separator: " ").last.map(String.init) ?? cleaned
    }

    var injectionInstruction: String {
        guard self != .none else { return "" }
        return "[Answer in the voice, tone, and philosophical style of \(rawValue). Adopt their worldview, vocabulary, and rhetorical patterns. Stay in character throughout.]"
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
    var aiResponseLengthPreset: String {
        get { defaults.string(forKey: "aiResponseLengthPreset") ?? AIResponseLengthPreset.l.rawValue }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiResponseLengthPreset") }
    }
    var aiResponseModePreset: String {
        get { defaults.string(forKey: "aiResponseModePreset") ?? AIResponseModePreset.none.rawValue }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiResponseModePreset") }
    }
    var aiExpertDisciplinePreset: String {
        get { defaults.string(forKey: "aiExpertDisciplinePreset") ?? AIExpertDisciplinePreset.none.rawValue }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiExpertDisciplinePreset") }
    }
    var aiVoiceFigurePreset: String {
        get { defaults.string(forKey: "aiVoiceFigurePreset") ?? AIVoiceFigurePreset.none.rawValue }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "aiVoiceFigurePreset") }
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

    var aiResponseLengthPresetEnum: AIResponseLengthPreset {
        get { AIResponseLengthPreset(rawValue: aiResponseLengthPreset) ?? .l }
        set { aiResponseLengthPreset = newValue.rawValue }
    }

    var aiResponseModePresetEnum: AIResponseModePreset {
        get { AIResponseModePreset(rawValue: aiResponseModePreset) ?? .none }
        set { aiResponseModePreset = newValue.rawValue }
    }

    var aiExpertDisciplinePresetEnum: AIExpertDisciplinePreset {
        get { AIExpertDisciplinePreset(rawValue: aiExpertDisciplinePreset) ?? .none }
        set { aiExpertDisciplinePreset = newValue.rawValue }
    }

    var aiVoiceFigurePresetEnum: AIVoiceFigurePreset {
        get { AIVoiceFigurePreset(rawValue: aiVoiceFigurePreset) ?? .none }
        set { aiVoiceFigurePreset = newValue.rawValue }
    }

    var aiResponseLengthInjection: String {
        aiResponseLengthPresetEnum.injectionInstruction
    }

    var aiResponseModeInjection: String {
        aiResponseModePresetEnum.injectionInstruction
    }

    var aiExpertDisciplineInjection: String {
        aiExpertDisciplinePresetEnum.injectionInstruction
    }

    var aiVoiceFigureInjection: String {
        aiVoiceFigurePresetEnum.injectionInstruction
    }

    var aiPromptSummaryChip: String {
        SettingsManager.makeAIPromptSummaryChip(
            length: aiResponseLengthPresetEnum,
            mode: aiResponseModePresetEnum,
            expert: aiExpertDisciplinePresetEnum,
            voice: aiVoiceFigurePresetEnum
        )
    }

    static func makeAIPromptSummaryChip(
        length: AIResponseLengthPreset,
        mode: AIResponseModePreset,
        expert: AIExpertDisciplinePreset,
        voice: AIVoiceFigurePreset
    ) -> String {
        var parts: [String] = []
        if length != .l {
            parts.append(length.rawValue)
        }
        if mode != .none {
            parts.append(mode.rawValue)
        }
        if expert != .none {
            parts.append(expert.rawValue)
        }
        if voice != .none {
            parts.append(voice.summaryLabel)
        }
        return parts.isEmpty ? "AI" : parts.joined(separator: " • ")
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
