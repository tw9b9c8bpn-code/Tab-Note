import Foundation

enum PromptInjectionDimensionID: String, CaseIterable, Codable {
    case responseLength = "response_length"
    case responseMode = "response_mode"
    case expertMode = "expert_mode"
    case voiceMode = "voice_mode"
}

enum PromptInjectionSelectionKind: String, Decodable {
    case singleRequired = "single_required"
    case singleOptional = "single_optional"
    case multiOptional = "multi_optional"
}

struct PromptInjectionOption: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
    let shortLabel: String?
    let helper: String?
    let prompt: String?
    let expertTitle: String?
    let roleName: String?
    let icon: String?
    let portraitAsset: String?
    let maxTokens: Int?
    let summaryLabel: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case shortLabel = "short_label"
        case helper
        case prompt
        case expertTitle = "expert_title"
        case roleName = "role_name"
        case icon
        case portraitAsset = "portrait_asset"
        case maxTokens = "max_tokens"
        case summaryLabel = "summary_label"
    }
}

struct PromptInjectionDimension: Decodable {
    let label: String
    let selection: PromptInjectionSelectionKind?
    let items: [PromptInjectionOption]
}

struct PromptInjectionCatalog: Decodable {
    let version: String
    let source: String?
    let compositionOrder: [PromptInjectionDimensionID]
    let dimensions: [String: PromptInjectionDimension]

    private enum CodingKeys: String, CodingKey {
        case version
        case source
        case compositionOrder = "composition_order"
        case dimensions
    }

    func dimension(_ id: PromptInjectionDimensionID) -> PromptInjectionDimension? {
        dimensions[id.rawValue]
    }
}

struct PromptInjectionDimensionRule: Decodable {
    let selection: PromptInjectionSelectionKind?
    let maxSelected: Int?
    let launcherStyle: String?
    let availableItems: [String]?

    private enum CodingKeys: String, CodingKey {
        case selection
        case maxSelected = "max_selected"
        case launcherStyle = "launcher_style"
        case availableItems = "available_items"
    }
}

struct PromptInjectionUIContract: Decodable {
    let dimensionRules: [String: PromptInjectionDimensionRule]

    private enum CodingKeys: String, CodingKey {
        case dimensionRules = "dimension_rules"
    }

    func rule(for id: PromptInjectionDimensionID) -> PromptInjectionDimensionRule? {
        dimensionRules[id.rawValue]
    }
}

struct PromptInjectionProfileDefaults: Decodable {
    let responseLength: String
    let responseMode: [String]
    let expertMode: [String]
    let voiceMode: String?

    private enum CodingKeys: String, CodingKey {
        case responseLength = "response_length"
        case responseMode = "response_mode"
        case expertMode = "expert_mode"
        case voiceMode = "voice_mode"
    }
}

struct PromptInjectionProfile: Decodable {
    let version: String
    let defaults: PromptInjectionProfileDefaults
    let uiContract: PromptInjectionUIContract

    private enum CodingKeys: String, CodingKey {
        case version
        case defaults
        case uiContract = "ui_contract"
    }
}

struct PromptInjectionSelection: Codable, Equatable {
    var responseLengthID: String
    var responseModeIDs: Set<String>
    var expertModeIDs: Set<String>
    var voiceModeID: String?

    init(
        responseLengthID: String,
        responseModeIDs: Set<String> = [],
        expertModeIDs: Set<String> = [],
        voiceModeID: String? = nil
    ) {
        self.responseLengthID = responseLengthID
        self.responseModeIDs = responseModeIDs
        self.expertModeIDs = expertModeIDs
        self.voiceModeID = voiceModeID
    }
}

struct PromptInjectionConfiguration {
    let catalog: PromptInjectionCatalog
    let profile: PromptInjectionProfile

    var responseLengthOptions: [PromptInjectionOption] { items(for: .responseLength) }
    var responseModeOptions: [PromptInjectionOption] { items(for: .responseMode) }
    var expertModeOptions: [PromptInjectionOption] { items(for: .expertMode) }
    var voiceModeOptions: [PromptInjectionOption] { items(for: .voiceMode) }

    var defaultSelection: PromptInjectionSelection {
        let defaults = profile.defaults
        return PromptInjectionSelection(
            responseLengthID: normalizedResponseLengthID(defaults.responseLength),
            responseModeIDs: normalizedMultiSelectionIDs(defaults.responseMode, dimension: .responseMode),
            expertModeIDs: normalizedMultiSelectionIDs(defaults.expertMode, dimension: .expertMode),
            voiceModeID: normalizedOptionalSelectionID(defaults.voiceMode, dimension: .voiceMode)
        )
    }

    func items(for dimension: PromptInjectionDimensionID) -> [PromptInjectionOption] {
        guard let baseItems = catalog.dimension(dimension)?.items else { return [] }
        guard let allowedItems = profile.uiContract.rule(for: dimension)?.availableItems, !allowedItems.isEmpty else {
            return baseItems
        }

        let allowed = Set(allowedItems)
        return baseItems.filter { allowed.contains($0.id) }
    }

    func responseLengthOption(id: String?) -> PromptInjectionOption? {
        option(for: id, in: .responseLength)
    }

    func responseModeOption(id: String?) -> PromptInjectionOption? {
        option(for: id, in: .responseMode)
    }

    func expertModeOption(id: String?) -> PromptInjectionOption? {
        option(for: id, in: .expertMode)
    }

    func voiceModeOption(id: String?) -> PromptInjectionOption? {
        option(for: id, in: .voiceMode)
    }

    func selectedResponseModes(from ids: Set<String>) -> [PromptInjectionOption] {
        selectedOptions(in: .responseMode, ids: ids)
    }

    func selectedExpertModes(from ids: Set<String>) -> [PromptInjectionOption] {
        selectedOptions(in: .expertMode, ids: ids)
    }

    func normalized(_ selection: PromptInjectionSelection) -> PromptInjectionSelection {
        PromptInjectionSelection(
            responseLengthID: normalizedResponseLengthID(selection.responseLengthID),
            responseModeIDs: normalizedMultiSelectionIDs(selection.responseModeIDs, dimension: .responseMode),
            expertModeIDs: normalizedMultiSelectionIDs(selection.expertModeIDs, dimension: .expertMode),
            voiceModeID: normalizedOptionalSelectionID(selection.voiceModeID, dimension: .voiceMode)
        )
    }

    func normalizedResponseLengthID(_ value: String?) -> String {
        normalizedRequiredSelectionID(value, dimension: .responseLength)
    }

    func normalizedOptionalSelectionID(_ value: String?, dimension: PromptInjectionDimensionID) -> String? {
        normalizedOrderedIDs(value.map { [$0] } ?? [], dimension: dimension).first
    }

    func normalizedMultiSelectionIDs<S: Sequence>(_ values: S, dimension: PromptInjectionDimensionID) -> Set<String> where S.Element == String {
        Set(normalizedOrderedIDs(values, dimension: dimension))
    }

    func instruction(for selection: PromptInjectionSelection) -> String {
        let resolved = normalized(selection)
        var instructions: [String] = []

        if let prompt = responseLengthOption(id: resolved.responseLengthID)?.prompt?.trimmedNonEmpty {
            instructions.append(prompt)
        }

        for option in selectedResponseModes(from: resolved.responseModeIDs) {
            if let prompt = option.prompt?.trimmedNonEmpty {
                instructions.append(prompt)
            }
        }

        let expertRoles = selectedExpertModes(from: resolved.expertModeIDs)
            .compactMap(\.roleName)

        if !expertRoles.isEmpty {
            instructions.append("[Act as \(joinedRoles(expertRoles))]")
        }

        if let prompt = voiceModeOption(id: resolved.voiceModeID)?.prompt?.trimmedNonEmpty {
            instructions.append(prompt)
        }

        return instructions.joined(separator: "\n")
    }

    func summaryChip(for selection: PromptInjectionSelection) -> String {
        let resolved = normalized(selection)
        let defaults = defaultSelection
        var parts: [String] = []

        if resolved.responseLengthID != defaults.responseLengthID,
           let option = responseLengthOption(id: resolved.responseLengthID) {
            parts.append(option.label)
        }

        parts.append(contentsOf: selectedResponseModes(from: resolved.responseModeIDs).map {
            $0.shortLabel ?? $0.label
        })

        parts.append(contentsOf: selectedExpertModes(from: resolved.expertModeIDs).map {
            $0.shortLabel ?? $0.expertTitle ?? $0.label
        })

        if let voiceModeID = resolved.voiceModeID {
            parts.append(voiceSummaryLabel(for: voiceModeID))
        }

        return parts.isEmpty ? "AI" : parts.joined(separator: " • ")
    }

    func responseLengthMaxTokens(for id: String?) -> Int {
        responseLengthOption(id: id)?.maxTokens ?? 900
    }

    func responseModeMenuLabel(for id: String?) -> String {
        guard let option = responseModeOption(id: id) else { return "None" }
        guard let shortLabel = option.shortLabel else { return option.label }
        return "\(shortLabel) (\(option.label.lowercased()))"
    }

    func expertModeMenuLabel(for id: String?) -> String {
        guard let option = expertModeOption(id: id) else { return "None" }
        guard let shortLabel = option.shortLabel else { return option.expertTitle ?? option.label }
        return "\(shortLabel) (\(option.expertTitle ?? option.label))"
    }

    func voiceModeMenuLabel(for id: String?) -> String {
        voiceModeOption(id: id)?.label ?? "None"
    }

    func voiceSummaryLabel(for id: String?) -> String {
        guard let option = voiceModeOption(id: id) else { return "Voice" }
        if let summaryLabel = option.summaryLabel?.trimmedNonEmpty {
            return summaryLabel
        }

        let cleaned = option.label
            .replacingOccurrences(of: "Dr. ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.split(separator: " ").last.map(String.init) ?? cleaned
    }

    private func option(for id: String?, in dimension: PromptInjectionDimensionID) -> PromptInjectionOption? {
        guard let canonicalID = PromptInjectionLegacyMapping.canonicalID(from: id, dimension: dimension) else {
            return nil
        }
        return items(for: dimension).first(where: { $0.id == canonicalID })
    }

    private func selectedOptions(in dimension: PromptInjectionDimensionID, ids: Set<String>) -> [PromptInjectionOption] {
        let normalizedIDs = normalizedMultiSelectionIDs(ids, dimension: dimension)
        return items(for: dimension).filter { normalizedIDs.contains($0.id) }
    }

    private func normalizedRequiredSelectionID(_ value: String?, dimension: PromptInjectionDimensionID) -> String {
        if let first = normalizedOrderedIDs(value.map { [$0] } ?? [], dimension: dimension).first {
            return first
        }

        if let fallback = requiredFallbackID(for: dimension) {
            return fallback
        }

        return value ?? ""
    }

    private func normalizedOrderedIDs<S: Sequence>(_ values: S, dimension: PromptInjectionDimensionID) -> [String] where S.Element == String {
        let options = items(for: dimension)
        guard !options.isEmpty else { return [] }

        let canonicalIDs = Set(values.compactMap {
            PromptInjectionLegacyMapping.canonicalID(from: $0, dimension: dimension)
        })

        var orderedIDs = options
            .map(\.id)
            .filter { canonicalIDs.contains($0) }

        let selectionKind = profile.uiContract.rule(for: dimension)?.selection
            ?? catalog.dimension(dimension)?.selection
            ?? .multiOptional

        if selectionKind != .multiOptional || dimension == .voiceMode {
            orderedIDs = Array(orderedIDs.prefix(1))
        } else if let maxSelected = profile.uiContract.rule(for: dimension)?.maxSelected {
            orderedIDs = Array(orderedIDs.prefix(maxSelected))
        }

        if orderedIDs.isEmpty, selectionKind == .singleRequired, let fallback = requiredFallbackID(for: dimension) {
            return [fallback]
        }

        return orderedIDs
    }

    private func requiredFallbackID(for dimension: PromptInjectionDimensionID) -> String? {
        let options = items(for: dimension)
        guard !options.isEmpty else { return nil }

        let defaultValues: [String]
        switch dimension {
        case .responseLength:
            defaultValues = [profile.defaults.responseLength]
        case .responseMode:
            defaultValues = profile.defaults.responseMode
        case .expertMode:
            defaultValues = profile.defaults.expertMode
        case .voiceMode:
            defaultValues = profile.defaults.voiceMode.map { [$0] } ?? []
        }

        for value in defaultValues {
            if let canonicalID = PromptInjectionLegacyMapping.canonicalID(from: value, dimension: dimension),
               options.contains(where: { $0.id == canonicalID }) {
                return canonicalID
            }
        }

        return options.first?.id
    }

    private func joinedRoles(_ roles: [String]) -> String {
        switch roles.count {
        case 0:
            return ""
        case 1:
            return roles[0]
        case 2:
            return roles.joined(separator: " and ")
        default:
            return roles.dropLast().joined(separator: ", ") + " and " + roles[roles.count - 1]
        }
    }
}

enum PromptInjectionLegacyMapping {
    private static let responseLengthIDs: [String: String] = [
        "XS": "xs",
        "S": "s",
        "M": "m",
        "L": "l",
        "XL": "xl",
        "xs": "xs",
        "s": "s",
        "m": "m",
        "l": "l",
        "xl": "xl"
    ]

    private static let responseModeIDs: [String: String] = [
        "A": "analogy",
        "E": "example",
        "S": "socratic",
        "D": "dialog",
        "I": "inversion",
        "M": "manifesto",
        "R": "rant",
        "IS": "interactive_simulation",
        "T": "table_of_contents",
        "80": "pareto",
        "2O": "second_order",
        "TL": "tier_list",
        "FP": "first_principles",
        "NONE": "",
        "analogy": "analogy",
        "example": "example",
        "socratic": "socratic",
        "dialog": "dialog",
        "inversion": "inversion",
        "manifesto": "manifesto",
        "rant": "rant",
        "interactive_simulation": "interactive_simulation",
        "table_of_contents": "table_of_contents",
        "pareto": "pareto",
        "second_order": "second_order",
        "tier_list": "tier_list",
        "first_principles": "first_principles"
    ]

    private static let expertModeIDs: [String: String] = [
        "Phy": "physics",
        "Bio": "biology",
        "EvoBio": "evolutionary_biology",
        "Eco": "ecology",
        "Sys": "systems",
        "Gam": "game_theory",
        "Ecn": "economics",
        "Psy": "psychology",
        "Phi": "philosophy",
        "Lng": "linguistics",
        "Art": "arts",
        "Eng": "engineering",
        "Chm": "chemistry",
        "Tec": "technology",
        "Elc": "electrician",
        "Acc": "accountant",
        "Che": "chef",
        "Nut": "nutritionist",
        "Doc": "doctor",
        "Des": "designer",
        "Fen": "feng_shui",
        "Arc": "architect",
        "NONE": "",
        "physics": "physics",
        "biology": "biology",
        "evolutionary_biology": "evolutionary_biology",
        "ecology": "ecology",
        "systems": "systems",
        "game_theory": "game_theory",
        "economics": "economics",
        "psychology": "psychology",
        "philosophy": "philosophy",
        "linguistics": "linguistics",
        "arts": "arts",
        "engineering": "engineering",
        "chemistry": "chemistry",
        "technology": "technology",
        "electrician": "electrician",
        "accountant": "accountant",
        "chef": "chef",
        "nutritionist": "nutritionist",
        "doctor": "doctor",
        "designer": "designer",
        "feng_shui": "feng_shui",
        "architect": "architect"
    ]

    private static let voiceModeIDs: [String: String] = [
        "Ayn Rand": "ayn_rand",
        "Lee Kuan Yew": "lee_kuan_yew",
        "Eckhart Tolle": "eckhart_tolle",
        "Jiddu Krishnamurti": "jiddu_krishnamurti",
        "Aristotle": "aristotle",
        "Machiavelli": "machiavelli",
        "Nietzsche": "nietzsche",
        "Erich Fromm": "erich_fromm",
        "Michael Greger": "michael_greger",
        "Michael Saylor": "michael_saylor",
        "Maxwell Maltz": "maxwell_maltz",
        "Byung-Chul Han": "byung_chul_han",
        "Harry Browne": "harry_browne",
        "Seth Godin": "seth_godin",
        "Dr. Nicole LePera": "nicole_lepera",
        "Richard Koch": "richard_koch",
        "Jeff Bezos": "jeff_bezos",
        "Sun Tzu": "sun_tzu",
        "Leonardo da Vinci": "leonardo_da_vinci",
        "Naval Ravikant": "naval_ravikant",
        "NONE": "",
        "ayn_rand": "ayn_rand",
        "lee_kuan_yew": "lee_kuan_yew",
        "eckhart_tolle": "eckhart_tolle",
        "jiddu_krishnamurti": "jiddu_krishnamurti",
        "aristotle": "aristotle",
        "machiavelli": "machiavelli",
        "nietzsche": "nietzsche",
        "erich_fromm": "erich_fromm",
        "michael_greger": "michael_greger",
        "michael_saylor": "michael_saylor",
        "maxwell_maltz": "maxwell_maltz",
        "byung_chul_han": "byung_chul_han",
        "harry_browne": "harry_browne",
        "seth_godin": "seth_godin",
        "nicole_lepera": "nicole_lepera",
        "richard_koch": "richard_koch",
        "jeff_bezos": "jeff_bezos",
        "sun_tzu": "sun_tzu",
        "leonardo_da_vinci": "leonardo_da_vinci",
        "naval_ravikant": "naval_ravikant"
    ]

    static func canonicalID(from value: String?, dimension: PromptInjectionDimensionID) -> String? {
        guard let trimmed = value?.trimmedNonEmpty else { return nil }

        let mapped: String?
        switch dimension {
        case .responseLength:
            mapped = responseLengthIDs[trimmed]
        case .responseMode:
            mapped = responseModeIDs[trimmed]
        case .expertMode:
            mapped = expertModeIDs[trimmed]
        case .voiceMode:
            mapped = voiceModeIDs[trimmed]
        }

        guard let mapped, !mapped.isEmpty else { return nil }
        return mapped
    }
}

final class PromptInjectionConfigurationStore {
    static let shared = PromptInjectionConfigurationStore(profileFileName: "tab-note.profile.json")

    let configuration: PromptInjectionConfiguration
    let sharedDirectoryURL: URL

    private init(profileFileName: String) {
        sharedDirectoryURL = Self.sharedDirectoryURL()
        configuration = Self.loadConfiguration(profileFileName: profileFileName, sharedDirectoryURL: sharedDirectoryURL)
    }

    private static func loadConfiguration(profileFileName: String, sharedDirectoryURL: URL) -> PromptInjectionConfiguration {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: sharedDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        copyBundledResourceIfMissing(
            fileName: "options.catalog.json",
            to: sharedDirectoryURL.appendingPathComponent("options.catalog.json")
        )
        copyBundledResourceIfMissing(
            fileName: profileFileName,
            to: sharedDirectoryURL.appendingPathComponent(profileFileName)
        )

        let catalog = decode(
            PromptInjectionCatalog.self,
            preferredURL: sharedDirectoryURL.appendingPathComponent("options.catalog.json"),
            bundledFileName: "options.catalog.json"
        )
        let profile = decode(
            PromptInjectionProfile.self,
            preferredURL: sharedDirectoryURL.appendingPathComponent(profileFileName),
            bundledFileName: profileFileName
        )

        return PromptInjectionConfiguration(catalog: catalog, profile: profile)
    }

    private static func decode<T: Decodable>(_ type: T.Type, preferredURL: URL, bundledFileName: String) -> T {
        if let preferredData = try? Data(contentsOf: preferredURL),
           let preferredValue = try? JSONDecoder().decode(T.self, from: preferredData) {
            return preferredValue
        }

        guard let bundledURL = bundledURL(for: bundledFileName),
              let bundledData = try? Data(contentsOf: bundledURL),
              let bundledValue = try? JSONDecoder().decode(T.self, from: bundledData) else {
            preconditionFailure("Missing bundled prompt injection resource: \(bundledFileName)")
        }

        return bundledValue
    }

    private static func copyBundledResourceIfMissing(fileName: String, to destinationURL: URL) {
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }
        guard let bundledURL = bundledURL(for: fileName) else { return }
        try? FileManager.default.copyItem(at: bundledURL, to: destinationURL)
    }

    private static func bundledURL(for fileName: String) -> URL? {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "PromptInjection")
    }

    private static func sharedDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/KienConfig", isDirectory: true)
            .appendingPathComponent("PromptInjection", isDirectory: true)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
