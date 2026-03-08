//
//  AIService.swift
//  Tab Note
//
//  Created by Kien Tran on 2026-03-03.
//

import Foundation

enum AIAction: String {
    case addContent = "addContent"
    case improvePrompt = "improvePrompt"
    case addSuggestions = "addSuggestions"
}

class AIService {
    static let shared = AIService()
    private var currentTask: URLSessionDataTask?
    private var currentStreamingTask: Task<Void, Never>?
    private init() {}

    private enum APITransport {
        case openAICompatible
        case anthropicCompatible
    }

    private struct APIDiagnosticProbe {
        let transport: APITransport
        let request: URLRequest
        let model: String
    }

    private struct AdvancedJSONModeConfig {
        let endpoint: String
        let method: String
        let headers: [String: String]
        let bodyTemplate: Any
        let responseTextPath: String?
        let streamingEnabled: Bool
        let streamTextPath: String?
        let streamLinePrefix: String
        let streamDoneToken: String
    }

    private struct PreparedAdvancedJSONRequest {
        let config: AdvancedJSONModeConfig
        let request: URLRequest
        let resolvedEndpoint: String
        let resolvedModel: String
    }

    struct InlineAnswerOptions {
        var aiMode: AIMode
        var endpoint: String
        var apiKey: String
        var apiHeaderName: String
        var model: String
        var apiRequestStyle: APIRequestStyle
        var advancedJSONConfiguration: String
        var promptSelection: PromptInjectionSelection

        init(
            aiMode: AIMode,
            endpoint: String,
            apiKey: String,
            apiHeaderName: String,
            model: String,
            apiRequestStyle: APIRequestStyle,
            advancedJSONConfiguration: String,
            promptSelection: PromptInjectionSelection
        ) {
            self.aiMode = aiMode
            self.endpoint = endpoint
            self.apiKey = apiKey
            self.apiHeaderName = apiHeaderName
            self.model = model
            self.apiRequestStyle = apiRequestStyle
            self.advancedJSONConfiguration = advancedJSONConfiguration
            self.promptSelection = PromptInjectionConfigurationStore.shared.configuration.normalized(promptSelection)
        }

        init(settings: SettingsManager) {
            let mode = settings.aiModeEnum
            self.init(
                aiMode: mode,
                endpoint: mode == .local ? settings.aiLocalEndpoint : settings.aiAPIEndpoint,
                apiKey: mode == .api ? settings.aiApiKey : "",
                apiHeaderName: mode == .api ? settings.aiAPIHeaderName : "Authorization",
                model: mode == .local ? settings.aiLocalModel : settings.currentAIModel,
                apiRequestStyle: mode == .api ? settings.aiAPIRequestStyleEnum : .standard,
                advancedJSONConfiguration: mode == .api ? settings.aiAPIAdvancedJSONConfiguration : "",
                promptSelection: settings.aiPromptSelection
            )
        }

        var summaryChip: String {
            SettingsManager.makeAIPromptSummaryChip(selection: promptSelection)
        }

        var maxTokens: Int {
            PromptInjectionConfigurationStore.shared.configuration.responseLengthMaxTokens(
                for: promptSelection.responseLengthID
            )
        }

        var customDirectives: String {
            PromptInjectionConfigurationStore.shared.configuration.instruction(for: promptSelection)
        }
    }

    var isRequestInFlight: Bool {
        currentTask != nil || currentStreamingTask != nil
    }

    enum AIError: LocalizedError {
        case noEndpoint, invalidURL, noAPIKey
        case requestFailed(String)
        case invalidResponse, noContent, cancelled

        var errorDescription: String? {
            switch self {
            case .noEndpoint: return "No AI endpoint configured"
            case .invalidURL: return "Invalid endpoint URL"
            case .noAPIKey: return "No API key configured"
            case .requestFailed(let msg): return "Request failed: \(msg)"
            case .invalidResponse: return "Invalid response from AI"
            case .noContent: return "No content in AI response"
            case .cancelled: return "Cancelled"
            }
        }
    }

    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
        currentStreamingTask?.cancel()
        currentStreamingTask = nil
    }

    // MARK: - Generate

    func generateContent(
        action: AIAction,
        noteContent: String,
        settings: SettingsManager,
        onStatus: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let systemPrompt: String
        let userMessage: String

        switch action {

        case .addContent:
            systemPrompt = """
            You are an AI writing assistant embedded in a note-taking app. \
            The user provides their current note content. \
            Your job: generate new content to ADD at the end of the note—do NOT rewrite or repeat existing text. \
            Output ONLY the new text to append. No preambles, no explanations, no summaries. \
            Match the tone and style of the existing note. \
            End with 1-2 follow-up ideas prefixed with "💡 ".
            """
            userMessage = """
            Existing note (do not repeat this):
            ---
            \(noteContent.isEmpty ? "(empty note)" : noteContent)
            ---
            Generate new content to append below the existing text.
            """

        case .improvePrompt:
            systemPrompt = """
            You are an expert AI agent prompt engineer. \
            The user's note contains a prompt or instructions intended for an AI agent. \
            Your job: rewrite and improve that prompt to be clearer, more specific, better structured, \
            and more effective for an AI agent to act on. \
            Fix ambiguity, add missing context, improve action clarity. \
            Output format: Start with the bold heading "**AI Improved Prompt**" on its own line, \
            then output ONLY the improved prompt text. \
            Do not explain what you changed. Do not output anything else.
            """
            userMessage = """
            Original prompt/note to improve:
            ---
            \(noteContent.isEmpty ? "(empty note)" : noteContent)
            ---
            Output the improved version starting with "**AI Improved Prompt**".
            """

        case .addSuggestions:
            systemPrompt = """
            You are an expert AI agent consultant. \
            The user's note contains a prompt, project, feature, or idea intended to be built or executed by an AI agent. \
            Your job: analyze the note and generate 3-5 specific, actionable suggestions for: \
            improvements, missing features, edge cases, better AI agent instructions, or implementation ideas. \
            Output format: Start with the bold heading "**AI Suggestions**" on its own line, \
            then list each suggestion as a bullet point starting with "• ". \
            Each suggestion must be concrete and directly relevant. \
            Do not explain your reasoning. Do not output anything outside this format.
            """
            userMessage = """
            Note/prompt to analyse:
            ---
            \(noteContent.isEmpty ? "(empty note)" : noteContent)
            ---
            Output suggestions starting with "**AI Suggestions**".
            """
        }

        switch settings.aiModeEnum {
        case .local:
            callOllama(endpoint: settings.aiLocalEndpoint,
                       model: settings.aiLocalModel.isEmpty ? "llama3" : settings.aiLocalModel,
                       systemPrompt: systemPrompt, userMessage: userMessage,
                       onStatus: onStatus, completion: completion)
        case .api:
            callConfiguredAPI(endpoint: settings.aiAPIEndpoint,
                              apiKey: settings.aiApiKey,
                              apiHeaderName: settings.aiAPIHeaderName,
                              model: settings.aiAPIModel.isEmpty ? "gpt-4" : settings.aiAPIModel,
                              requestStyle: settings.aiAPIRequestStyleEnum,
                              advancedJSONConfiguration: settings.aiAPIAdvancedJSONConfiguration,
                              systemPrompt: systemPrompt, userMessage: userMessage,
                              onStatus: onStatus, completion: completion)
        }
    }

    func answerQuestionSentence(
        sentence: String,
        settings: SettingsManager,
        onStatus: @escaping (String) -> Void,
        onPartial: @escaping (String) -> Void = { _ in },
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        answerQuestionSentence(
            sentence: sentence,
            options: InlineAnswerOptions(settings: settings),
            onStatus: onStatus,
            onPartial: onPartial,
            completion: completion
        )
    }

    func answerQuestionSentence(
        sentence: String,
        options: InlineAnswerOptions,
        onStatus: @escaping (String) -> Void,
        onPartial: @escaping (String) -> Void = { _ in },
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let question = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            completion(.failure(AIError.noContent))
            return
        }

        let customDirectives = options.customDirectives

        let systemPrompt = """
        You are an assistant embedded in a note editor. \
        Use the provided paragraph context to answer clearly and directly. \
        Follow any custom instructions exactly. \
        When it improves readability, use lightweight Markdown formatting \
        (short headings, bullet/numbered lists, and bold emphasis). \
        Separate paragraphs with a single blank line. \
        Never merge heading labels directly into body text. \
        Do not use code fences unless explicitly requested.
        """
        let userMessage = """
        Paragraph context:
        \(question)

        Custom instructions:
        \(customDirectives.isEmpty ? "(none)" : customDirectives)

        Formatting preference:
        Rich-text friendly Markdown is allowed when helpful for readability. \
        Keep paragraph separation clear with blank lines.

        Return only the answer text.
        """

        switch options.aiMode {
        case .local:
            callOllama(
                endpoint: options.endpoint,
                model: options.model.isEmpty ? "llama3" : options.model,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                streamResponse: true,
                onStatus: onStatus,
                onPartial: onPartial,
                completion: completion
            )
        case .api:
            callConfiguredAPI(
                endpoint: options.endpoint,
                apiKey: options.apiKey,
                apiHeaderName: options.apiHeaderName,
                model: options.model.isEmpty ? "gpt-4" : options.model,
                requestStyle: options.apiRequestStyle,
                advancedJSONConfiguration: options.advancedJSONConfiguration,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                temperature: 0.3,
                maxTokens: options.maxTokens,
                streamResponse: true,
                onStatus: onStatus,
                onPartial: onPartial,
                completion: completion
            )
        }
    }

    func answerFollowUpQuestion(
        question: String,
        paragraphContext: String,
        previousAnswer: String,
        options: InlineAnswerOptions,
        onStatus: @escaping (String) -> Void,
        onPartial: @escaping (String) -> Void = { _ in },
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            completion(.failure(AIError.noContent))
            return
        }

        let customDirectives = options.customDirectives

        let systemPrompt = """
        You are an assistant embedded in a note editor. \
        You are answering a follow-up question about a paragraph and a previous AI answer. \
        Use the original paragraph for grounding, then extend or clarify based on the user's follow-up. \
        Follow any custom instructions exactly. \
        When it improves readability, use lightweight Markdown formatting \
        (short headings, bullet/numbered lists, and bold emphasis). \
        Separate paragraphs with a single blank line. \
        Never merge heading labels directly into body text. \
        Do not use code fences unless explicitly requested.
        """

        let userMessage = """
        Original paragraph context:
        \(paragraphContext.trimmingCharacters(in: .whitespacesAndNewlines))

        Previous AI answer:
        \(previousAnswer.trimmingCharacters(in: .whitespacesAndNewlines))

        Follow-up question:
        \(trimmedQuestion)

        Custom instructions:
        \(customDirectives.isEmpty ? "(none)" : customDirectives)

        Formatting preference:
        Rich-text friendly Markdown is allowed when helpful for readability. \
        Keep paragraph separation clear with blank lines.

        Return only the answer text.
        """

        switch options.aiMode {
        case .local:
            callOllama(
                endpoint: options.endpoint,
                model: options.model.isEmpty ? "llama3" : options.model,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                streamResponse: true,
                onStatus: onStatus,
                onPartial: onPartial,
                completion: completion
            )
        case .api:
            callConfiguredAPI(
                endpoint: options.endpoint,
                apiKey: options.apiKey,
                apiHeaderName: options.apiHeaderName,
                model: options.model.isEmpty ? "gpt-4" : options.model,
                requestStyle: options.apiRequestStyle,
                advancedJSONConfiguration: options.advancedJSONConfiguration,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                temperature: 0.3,
                maxTokens: options.maxTokens,
                streamResponse: true,
                onStatus: onStatus,
                onPartial: onPartial,
                completion: completion
            )
        }
    }

    // MARK: - Diagnose

    func diagnose(settings: SettingsManager,
                  onStatus: @escaping (String) -> Void,
                  completion: @escaping (Result<String, Error>) -> Void) {
        let mode = settings.aiModeEnum
        onStatus("Testing connection...")
        switch mode {
        case .local:
            fetchLocalModels(endpoint: settings.aiLocalEndpoint) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let models):
                        var msg = "Connection successful ✅"
                        if !models.isEmpty {
                            msg += "\nModels:\n" + models.map { "  • \($0)" }.joined(separator: "\n")
                        }
                        completion(.success(msg))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        case .api:
            diagnoseConfiguredAPI(
                endpoint: settings.aiAPIEndpoint,
                apiKey: settings.aiApiKey,
                apiHeaderName: settings.aiAPIHeaderName,
                model: settings.aiAPIModel,
                requestStyle: settings.aiAPIRequestStyleEnum,
                advancedJSONConfiguration: settings.aiAPIAdvancedJSONConfiguration,
                completion: completion
            )
        }
    }

    func fetchLocalModels(
        endpoint: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let url = localModelsURL(endpoint: endpoint) else {
            completion(.failure(AIError.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                completion(.failure(AIError.requestFailed(self.requestFailureMessage(for: error))))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(AIError.invalidResponse))
                return
            }
            guard http.statusCode == 200 else {
                completion(.failure(AIError.requestFailed("HTTP \(http.statusCode): \(self.parseAPIErrorMessage(from: data))")))
                return
            }
            guard let data else {
                completion(.success([]))
                return
            }
            completion(.success(self.parseLocalModelNames(from: data)))
        }.resume()
    }

    // MARK: - Ollama

    private func callOllama(endpoint: String, model: String, systemPrompt: String, userMessage: String,
                            streamResponse: Bool = false,
                            onStatus: @escaping (String) -> Void,
                            onPartial: ((String) -> Void)? = nil,
                            completion: @escaping (Result<String, Error>) -> Void) {
        let base = endpoint.isEmpty ? "http://localhost:11434" : endpoint
        guard let url = URL(string: "\(base)/api/chat") else { completion(.failure(AIError.invalidURL)); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 180
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": userMessage]],
            "stream": streamResponse
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        if streamResponse {
            streamOllama(request: req, model: model, onStatus: onStatus, onPartial: onPartial, completion: completion)
            return
        }

        onStatus("Connecting to Ollama...")
        onStatus("Generating with \(model)...")
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if self?.currentTask === task {
                    self?.currentTask = nil
                }
                if let error = error as? URLError, error.code == .cancelled {
                    completion(.failure(AIError.cancelled)); return
                }
                if let error = error {
                    completion(.failure(AIError.requestFailed(self?.requestFailureMessage(for: error) ?? error.localizedDescription)))
                    return
                }
                guard let data = data else { completion(.failure(AIError.invalidResponse)); return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? [String: Any],
                   let content = msg["content"] as? String {
                    completion(.success(content)); return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let resp = json["response"] as? String {
                    completion(.success(resp)); return
                }
                let raw = String(data: data, encoding: .utf8) ?? "?"
                completion(.failure(AIError.requestFailed("Unexpected: \(raw.prefix(200))")))
            }
        }
        currentTask = task
        task?.resume()
    }

    // MARK: - API-compatible

    private func callConfiguredAPI(endpoint: String, apiKey: String, apiHeaderName: String, model: String,
                                   requestStyle: APIRequestStyle = .standard,
                                   advancedJSONConfiguration: String = "",
                                   systemPrompt: String, userMessage: String,
                                   temperature: Double = 0.7,
                                   maxTokens: Int = 1024,
                                   streamResponse: Bool = false,
                                   onStatus: @escaping (String) -> Void,
                                   onPartial: ((String) -> Void)? = nil,
                                   completion: @escaping (Result<String, Error>) -> Void) {
        if requestStyle == .json {
            callAdvancedJSONConfiguredAPI(
                rawConfiguration: advancedJSONConfiguration,
                fallbackEndpoint: endpoint,
                fallbackAPIKey: apiKey,
                fallbackAPIHeaderName: apiHeaderName,
                fallbackModel: model,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                streamResponse: streamResponse,
                onStatus: onStatus,
                onPartial: onPartial,
                completion: completion
            )
            return
        }
        if let configurationError = apiConfigurationError(for: apiKey) {
            completion(.failure(configurationError))
            return
        }
        switch apiTransport(for: endpoint) {
        case .openAICompatible:
            callOpenAICompatible(
                endpoint: endpoint,
                apiKey: apiKey,
                apiHeaderName: apiHeaderName,
                model: model,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                streamResponse: streamResponse,
                onStatus: onStatus,
                onPartial: onPartial,
                completion: completion
            )
        case .anthropicCompatible:
            callAnthropicCompatible(
                endpoint: endpoint,
                apiKey: apiKey,
                apiHeaderName: apiHeaderName,
                model: model,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                streamResponse: streamResponse,
                onStatus: onStatus,
                onPartial: onPartial,
                completion: completion
            )
        }
    }

    private func callOpenAICompatible(endpoint: String, apiKey: String, apiHeaderName: String, model: String,
                                      systemPrompt: String, userMessage: String,
                                      temperature: Double = 0.7,
                                      maxTokens: Int = 1024,
                                      streamResponse: Bool = false,
                                      onStatus: @escaping (String) -> Void,
                                      onPartial: ((String) -> Void)? = nil,
                                      completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else { completion(.failure(AIError.noAPIKey)); return }
        guard let url = apiTransportURL(
            endpoint: endpoint,
            transport: .openAICompatible,
            openAIPath: "/chat/completions",
            anthropicPath: "/v1/messages",
            defaultBase: "https://api.openai.com/v1"
        ) else { completion(.failure(AIError.invalidURL)); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyConfiguredAPIHeaders(
            to: &req,
            apiKey: apiKey,
            apiHeaderName: apiHeaderName,
            transport: .openAICompatible
        )
        req.timeoutInterval = 180
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": userMessage]],
            "stream": streamResponse
        ]
        body.merge(openAISamplingFields(model: model, temperature: temperature)) { _, new in new }
        body.merge(openAICompletionLimitField(model: model, maxTokens: maxTokens)) { _, new in new }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        if streamResponse {
            streamOpenAICompatible(request: req, model: model, onStatus: onStatus, onPartial: onPartial, completion: completion)
            return
        }

        onStatus("Connecting to API...")
        onStatus("Generating with \(model)...")
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if self?.currentTask === task {
                    self?.currentTask = nil
                }
                if let error = error as? URLError, error.code == .cancelled {
                    completion(.failure(AIError.cancelled)); return
                }
                if let error = error {
                    completion(.failure(AIError.requestFailed(self?.requestFailureMessage(for: error) ?? error.localizedDescription)))
                    return
                }
                guard let data = data else {
                    completion(.failure(AIError.invalidResponse)); return
                }
                do {
                    let content = try self?.openAIMessageContent(from: data) ?? ""
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        completion(.failure(AIError.noContent)); return
                    }
                    completion(.success(trimmed))
                } catch {
                    let errorMessage = self?.parseAPIErrorMessage(from: data) ?? "Unexpected response"
                    if case AIError.invalidResponse = error {
                        completion(.failure(AIError.requestFailed(errorMessage)))
                    } else {
                        completion(.failure(error))
                    }
                    return
                }
            }
        }
        currentTask = task
        task?.resume()
    }

    private func callAnthropicCompatible(endpoint: String, apiKey: String, apiHeaderName: String, model: String,
                                         systemPrompt: String, userMessage: String,
                                         temperature: Double = 0.7,
                                         maxTokens: Int = 1024,
                                         streamResponse: Bool = false,
                                         onStatus: @escaping (String) -> Void,
                                         onPartial: ((String) -> Void)? = nil,
                                         completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else { completion(.failure(AIError.noAPIKey)); return }
        guard let url = apiTransportURL(
            endpoint: endpoint,
            transport: .anthropicCompatible,
            openAIPath: "/chat/completions",
            anthropicPath: "/v1/messages",
            defaultBase: "https://api.minimax.io/anthropic"
        ) else { completion(.failure(AIError.invalidURL)); return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyConfiguredAPIHeaders(
            to: &req,
            apiKey: apiKey,
            apiHeaderName: apiHeaderName,
            transport: .anthropicCompatible
        )
        req.timeoutInterval = 180
        let body: [String: Any] = [
            "model": model,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage]],
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": streamResponse
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        if streamResponse {
            streamAnthropicCompatible(request: req, model: model, onStatus: onStatus, onPartial: onPartial, completion: completion)
            return
        }

        onStatus("Connecting to API...")
        onStatus("Generating with \(model)...")
        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if self?.currentTask === task {
                    self?.currentTask = nil
                }
                if let error = error as? URLError, error.code == .cancelled {
                    completion(.failure(AIError.cancelled)); return
                }
                if let error = error {
                    completion(.failure(AIError.requestFailed(self?.requestFailureMessage(for: error) ?? error.localizedDescription)))
                    return
                }
                guard let data else {
                    completion(.failure(AIError.invalidResponse)); return
                }
                do {
                    let content = try self?.anthropicMessageContent(from: data) ?? ""
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        completion(.failure(AIError.noContent))
                    } else {
                        completion(.success(trimmed))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
        currentTask = task
        task?.resume()
    }

    private func callAdvancedJSONConfiguredAPI(
        rawConfiguration: String,
        fallbackEndpoint: String,
        fallbackAPIKey: String,
        fallbackAPIHeaderName: String,
        fallbackModel: String,
        systemPrompt: String,
        userMessage: String,
        temperature: Double,
        maxTokens: Int,
        streamResponse: Bool,
        onStatus: @escaping (String) -> Void,
        onPartial: ((String) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let prepared: PreparedAdvancedJSONRequest
        do {
            prepared = try preparedAdvancedJSONRequest(
                rawConfiguration: rawConfiguration,
                fallbackEndpoint: fallbackEndpoint,
                fallbackAPIKey: fallbackAPIKey,
                fallbackAPIHeaderName: fallbackAPIHeaderName,
                fallbackModel: fallbackModel,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                streamResponse: streamResponse
            )
        } catch {
            completion(.failure(error))
            return
        }

        if streamResponse && prepared.config.streamingEnabled {
            streamAdvancedJSON(
                preparedRequest: prepared,
                onStatus: onStatus,
                onPartial: onPartial,
                completion: completion
            )
            return
        }

        onStatus("Connecting to API...")
        onStatus("Sending custom JSON request...")

        var task: URLSessionDataTask?
        task = URLSession.shared.dataTask(with: prepared.request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if self?.currentTask === task {
                    self?.currentTask = nil
                }
                if let error = error as? URLError, error.code == .cancelled {
                    completion(.failure(AIError.cancelled))
                    return
                }
                if let error {
                    completion(.failure(AIError.requestFailed(self?.requestFailureMessage(for: error) ?? error.localizedDescription)))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(AIError.invalidResponse))
                    return
                }
                guard let data else {
                    completion(.failure(AIError.invalidResponse))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    completion(.failure(AIError.requestFailed("HTTP \(http.statusCode): \(self?.parseAPIErrorMessage(from: data) ?? "Unexpected response")")))
                    return
                }

                do {
                    let content = try self?.advancedJSONResponseText(
                        from: data,
                        textPath: prepared.config.responseTextPath
                    ) ?? ""
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        completion(.failure(AIError.noContent))
                    } else {
                        completion(.success(trimmed))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
        currentTask = task
        task?.resume()
    }

    private func diagnoseAdvancedJSONConfiguredAPI(
        rawConfiguration: String,
        fallbackEndpoint: String,
        fallbackAPIKey: String,
        fallbackAPIHeaderName: String,
        fallbackModel: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let prepared: PreparedAdvancedJSONRequest
        do {
            prepared = try preparedAdvancedJSONRequest(
                rawConfiguration: rawConfiguration,
                fallbackEndpoint: fallbackEndpoint,
                fallbackAPIKey: fallbackAPIKey,
                fallbackAPIHeaderName: fallbackAPIHeaderName,
                fallbackModel: fallbackModel,
                systemPrompt: "You are a connectivity test. Reply with OK.",
                userMessage: "Reply with OK.",
                temperature: 0,
                maxTokens: 8,
                streamResponse: false
            )
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: prepared.request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(AIError.requestFailed(self?.requestFailureMessage(for: error) ?? error.localizedDescription)))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(AIError.invalidResponse))
                    return
                }
                guard let data else {
                    completion(.failure(AIError.invalidResponse))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    completion(.failure(AIError.requestFailed("HTTP \(http.statusCode): \(self?.parseAPIErrorMessage(from: data) ?? "Unexpected response")")))
                    return
                }

                do {
                    let content = try self?.advancedJSONResponseText(
                        from: data,
                        textPath: prepared.config.responseTextPath
                    ) ?? ""
                    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        completion(.failure(AIError.noContent))
                        return
                    }

                    completion(.success("""
                    API connection successful ✅
                    Protocol: Advanced JSON
                    Endpoint: \(prepared.resolvedEndpoint)
                    """))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    private func preparedAdvancedJSONRequest(
        rawConfiguration: String,
        fallbackEndpoint: String,
        fallbackAPIKey: String,
        fallbackAPIHeaderName: String,
        fallbackModel: String,
        systemPrompt: String,
        userMessage: String,
        temperature: Double,
        maxTokens: Int,
        streamResponse: Bool
    ) throws -> PreparedAdvancedJSONRequest {
        let config = try parseAdvancedJSONConfiguration(
            rawConfiguration,
            fallbackEndpoint: fallbackEndpoint
        )

        let resolvedEndpoint = interpolatedTemplateString(
            config.endpoint,
            context: placeholderContext(
                endpoint: fallbackEndpoint,
                apiKey: fallbackAPIKey,
                apiHeaderName: fallbackAPIHeaderName,
                model: fallbackModel,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                temperature: temperature,
                maxTokens: maxTokens,
                streamResponse: streamResponse
            )
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: resolvedEndpoint), !resolvedEndpoint.isEmpty else {
            throw AIError.invalidURL
        }

        let placeholderValues = placeholderContext(
            endpoint: resolvedEndpoint,
            apiKey: fallbackAPIKey,
            apiHeaderName: fallbackAPIHeaderName,
            model: fallbackModel,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            temperature: temperature,
            maxTokens: maxTokens,
            streamResponse: streamResponse
        )

        let resolvedBody = resolveJSONTemplate(config.bodyTemplate, context: placeholderValues)
        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: resolvedBody, options: [.fragmentsAllowed])
        } catch {
            throw AIError.requestFailed("Advanced JSON body is not valid after placeholder replacement.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = config.method
        request.timeoutInterval = 180

        let resolvedHeaders = Dictionary(uniqueKeysWithValues: config.headers.map { key, value in
            (
                key,
                interpolatedTemplateString(value, context: placeholderValues)
            )
        })

        for (header, value) in resolvedHeaders where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: header)
        }

        if !resolvedHeaders.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        request.httpBody = bodyData
        let resolvedModel: String
        if let body = resolvedBody as? [String: Any],
           let model = body["model"] as? String {
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            resolvedModel = trimmedModel.isEmpty ? fallbackModel : trimmedModel
        } else {
            resolvedModel = fallbackModel
        }
        return PreparedAdvancedJSONRequest(
            config: config,
            request: request,
            resolvedEndpoint: resolvedEndpoint,
            resolvedModel: resolvedModel
        )
    }

    private func parseAdvancedJSONConfiguration(
        _ rawConfiguration: String,
        fallbackEndpoint: String
    ) throws -> AdvancedJSONModeConfig {
        let trimmed = rawConfiguration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIError.requestFailed("Advanced JSON mode is empty. Paste a JSON configuration first.")
        }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw AIError.requestFailed("Advanced JSON configuration is not valid JSON.")
        }

        let endpoint = (json["endpoint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let method = ((json["method"] as? String)?.uppercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "POST"
        let headers = (json["headers"] as? [String: Any] ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key] = stringifyTemplateValue(entry.value)
        }

        guard let bodyTemplate = json["body"] else {
            throw AIError.requestFailed("Advanced JSON configuration is missing `body`.")
        }

        let response = json["response"] as? [String: Any]
        let streaming = json["streaming"] as? [String: Any]

        return AdvancedJSONModeConfig(
            endpoint: (endpoint?.isEmpty == false ? endpoint! : fallbackEndpoint),
            method: method,
            headers: headers,
            bodyTemplate: bodyTemplate,
            responseTextPath: (response?["text_path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            streamingEnabled: streaming?["enabled"] as? Bool ?? false,
            streamTextPath: (streaming?["text_path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            streamLinePrefix: (streaming?["prefix"] as? String) ?? "data:",
            streamDoneToken: (streaming?["done_token"] as? String) ?? "[DONE]"
        )
    }

    private func placeholderContext(
        endpoint: String,
        apiKey: String,
        apiHeaderName: String,
        model: String,
        systemPrompt: String,
        userMessage: String,
        temperature: Double,
        maxTokens: Int,
        streamResponse: Bool
    ) -> [String: Any] {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKey = rawAPIKeyValue(from: apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let bearerKey = rawKey.isEmpty ? "" : "Bearer \(rawKey)"
        let completionLimit = usesMaxCompletionTokens(for: trimmedModel) ? maxTokens : maxTokens

        return [
            "endpoint": endpoint,
            "api_key": rawKey,
            "api_key_bearer": bearerKey,
            "api_header_name": normalizedAPIHeaderName(apiHeaderName),
            "model": trimmedModel,
            "system_prompt": systemPrompt,
            "user_message": userMessage,
            "temperature": temperature,
            "stream": streamResponse,
            "max_tokens": maxTokens,
            "max_completion_tokens": completionLimit
        ]
    }

    private func resolveJSONTemplate(_ value: Any, context: [String: Any]) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = resolveJSONTemplate(entry.value, context: context)
            }
        }
        if let array = value as? [Any] {
            return array.map { resolveJSONTemplate($0, context: context) }
        }
        guard let string = value as? String else { return value }

        if let exactKey = exactPlaceholderKey(in: string), let replacement = context[exactKey] {
            return replacement
        }

        return interpolatedTemplateString(string, context: context)
    }

    private func exactPlaceholderKey(in string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{{"), trimmed.hasSuffix("}}") else { return nil }
        let body = trimmed.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    private func interpolatedTemplateString(_ template: String, context: [String: Any]) -> String {
        var result = template
        for (key, value) in context {
            result = result.replacingOccurrences(
                of: "{{\(key)}}",
                with: stringifyTemplateValue(value)
            )
        }
        return result
    }

    private func stringifyTemplateValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return "\(value)"
        }
    }

    private func advancedJSONResponseText(from data: Data, textPath: String?) throws -> String {
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            if let message = apiErrorMessage(from: json), !message.isEmpty {
                throw AIError.requestFailed(message)
            }
            if let text = extractedAdvancedJSONText(from: json, explicitTextPath: textPath, streaming: false) {
                return text
            }
            if let hint = advancedJSONEmptyResponseHint(from: json) {
                throw AIError.requestFailed(hint)
            }
            throw AIError.requestFailed("No response text found. Add `response.text_path` to the Advanced JSON configuration.")
        }

        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            return raw
        }
        throw AIError.noContent
    }

    private func apiErrorMessage(from json: Any) -> String? {
        guard let dictionary = json as? [String: Any] else { return nil }
        if let error = dictionary["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        if let error = dictionary["error"] as? String, !error.isEmpty {
            return error
        }
        if let detail = dictionary["message"] as? String, !detail.isEmpty {
            return detail
        }
        return nil
    }

    private func requestFailureMessage(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return error.localizedDescription
        }

        switch urlError.code {
        case .networkConnectionLost:
            return "The network connection dropped during the request. This is usually a transient macOS/provider transport interruption. Retry once."
        case .timedOut:
            return "The request timed out before the provider finished responding. Retry once or reduce the response length."
        case .notConnectedToInternet:
            return "No internet connection is available for the request."
        case .cannotConnectToHost:
            return "Could not connect to the provider host. Check the endpoint and try again."
        case .cannotFindHost:
            return "Could not find the provider host. Check the endpoint and try again."
        default:
            return urlError.localizedDescription
        }
    }

    private func jsonValue(at path: String, in root: Any) -> Any? {
        let segments = path.split(separator: ".").map(String.init)
        guard !segments.isEmpty else { return nil }

        var current: Any? = root
        for segment in segments {
            if let index = Int(segment), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dictionary = current as? [String: Any] {
                current = dictionary[segment]
            } else {
                return nil
            }
        }
        return current
    }

    private func stringContent(from value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            let joined = array.compactMap { stringContent(from: $0) }.joined()
            return joined.isEmpty ? nil : joined
        case let dictionary as [String: Any]:
            if let text = dictionary["text"] as? String {
                return text
            }
            if let content = dictionary["content"] as? String {
                return content
            }
            return nil
        default:
            return nil
        }
    }

    private func extractedAdvancedJSONText(from json: Any, explicitTextPath: String?, streaming: Bool) -> String? {
        if let explicitTextPath,
           let text = textAtAdvancedJSONPath(explicitTextPath, in: json) {
            return text
        }

        for candidatePath in commonAdvancedJSONTextPaths(streaming: streaming) {
            if let text = textAtAdvancedJSONPath(candidatePath, in: json) {
                return text
            }
        }
        return nil
    }

    private func textAtAdvancedJSONPath(_ path: String, in json: Any) -> String? {
        guard let value = jsonValue(at: path, in: json),
              let text = stringContent(from: value)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func commonAdvancedJSONTextPaths(streaming: Bool) -> [String] {
        if streaming {
            return [
                "choices.0.delta.content",
                "choices.0.text",
                "delta.text",
                "content_block.text",
                "message.content"
            ]
        }
        return [
            "choices.0.message.content",
            "choices.0.text",
            "content.0.text",
            "output_text",
            "output.0.content.0.text",
            "message.content"
        ]
    }

    private func advancedJSONEmptyResponseHint(from json: Any) -> String? {
        let finishReasonPaths = [
            "choices.0.finish_reason",
            "choices.0.finishreason",
            "stop_reason"
        ]
        for path in finishReasonPaths {
            guard let finishReason = jsonValue(at: path, in: json) as? String else { continue }
            if finishReason.caseInsensitiveCompare("length") == .orderedSame {
                return "Model returned no visible content before hitting the token limit. Increase `max_completion_tokens` or change the JSON body."
            }
        }

        if let refusal = jsonValue(at: "choices.0.message.refusal", in: json) as? String,
           !refusal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return refusal
        }

        let reasoningTokenPaths = [
            "usage.completion_tokens_details.reasoning_tokens",
            "usage.completiontokensdetails.reasoningtokens"
        ]
        for path in reasoningTokenPaths {
            guard let reasoningTokens = jsonValue(at: path, in: json) as? NSNumber else { continue }
            if reasoningTokens.intValue > 0,
               extractedAdvancedJSONText(from: json, explicitTextPath: nil, streaming: false) == nil {
                return "The provider spent tokens on reasoning but returned no visible answer. Increase `max_completion_tokens` or adjust the JSON request."
            }
        }

        return nil
    }

    private func streamAdvancedJSON(
        preparedRequest: PreparedAdvancedJSONRequest,
        onStatus: @escaping (String) -> Void,
        onPartial: ((String) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        onStatus("Connecting to API...")
        onStatus("Streaming custom JSON request...")

        currentStreamingTask = Task { [weak self] in
            var aggregated = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: preparedRequest.request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw AIError.requestFailed("HTTP \(http.statusCode)")
                }

                let prefix = preparedRequest.config.streamLinePrefix
                let doneToken = preparedRequest.config.streamDoneToken
                let textPath = preparedRequest.config.streamTextPath

                streamLoop: for try await line in bytes.lines {
                    try Task.checkCancellation()
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    let payload: String
                    if prefix.isEmpty {
                        payload = trimmed
                    } else {
                        guard trimmed.hasPrefix(prefix) else { continue }
                        payload = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    guard !payload.isEmpty else { continue }
                    if payload == doneToken {
                        break streamLoop
                    }

                    let chunk: String
                    if let textPath, !textPath.isEmpty {
                        guard let payloadData = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: payloadData, options: [.fragmentsAllowed]) else {
                            continue
                        }
                        if let message = self?.apiErrorMessage(from: json), !message.isEmpty {
                            throw AIError.requestFailed(message)
                        }
                        guard let value = self?.jsonValue(at: textPath, in: json),
                              let text = self?.stringContent(from: value),
                              !text.isEmpty else {
                            continue
                        }
                        chunk = text
                    } else {
                        if let payloadData = payload.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: payloadData, options: [.fragmentsAllowed]) {
                            if let message = self?.apiErrorMessage(from: json), !message.isEmpty {
                                throw AIError.requestFailed(message)
                            }
                            guard let extracted = self?.extractedAdvancedJSONText(from: json, explicitTextPath: nil, streaming: true),
                                  !extracted.isEmpty else {
                                continue
                            }
                            chunk = extracted
                        } else {
                            chunk = payload
                        }
                    }

                    aggregated += chunk
                    if let onPartial {
                        await MainActor.run { onPartial(aggregated) }
                    }
                }

                let finalText = aggregated.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    if finalText.isEmpty {
                        completion(.failure(AIError.noContent))
                    } else {
                        completion(.success(finalText))
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(AIError.cancelled))
                }
            } catch let error as AIError {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(error))
                }
            } catch {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(AIError.requestFailed(self?.requestFailureMessage(for: error) ?? error.localizedDescription)))
                }
            }
        }
    }

    private func normalizedAPIHeaderName(_ headerName: String) -> String {
        let trimmed = headerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Authorization" : trimmed
    }

    private func apiHeaderValue(for headerName: String, apiKey: String) -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if headerName.caseInsensitiveCompare("x-api-key") == .orderedSame {
            return rawAPIKeyValue(from: trimmedKey)
        }
        guard headerName.caseInsensitiveCompare("Authorization") == .orderedSame else {
            return trimmedKey
        }
        let lowercasedValue = trimmedKey.lowercased()
        if lowercasedValue.hasPrefix("bearer ") || lowercasedValue.hasPrefix("basic ") {
            return trimmedKey
        }
        return "Bearer \(trimmedKey)"
    }

    private func rawAPIKeyValue(from apiKey: String) -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmedKey.lowercased()
        if lowercased.hasPrefix("bearer ") {
            return String(trimmedKey.dropFirst(7))
        }
        if lowercased.hasPrefix("basic ") {
            return String(trimmedKey.dropFirst(6))
        }
        return trimmedKey
    }

    private func apiTransport(for endpoint: String) -> APITransport {
        endpoint.lowercased().contains("/anthropic") ? .anthropicCompatible : .openAICompatible
    }

    private func apiTransportURL(
        endpoint: String,
        transport: APITransport,
        openAIPath: String,
        anthropicPath: String,
        defaultBase: String
    ) -> URL? {
        let base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultBase
            : endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let path = transport == .anthropicCompatible ? anthropicPath : openAIPath
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: normalizedBase + normalizedPath)
    }

    private func apiTransportDisplayName(_ transport: APITransport) -> String {
        switch transport {
        case .openAICompatible:
            return "OpenAI-compatible"
        case .anthropicCompatible:
            return "Anthropic-compatible"
        }
    }

    private func applyConfiguredAPIHeaders(
        to request: inout URLRequest,
        apiKey: String,
        apiHeaderName: String,
        transport: APITransport
    ) {
        let headerName = normalizedAPIHeaderName(apiHeaderName)
        request.setValue(apiHeaderValue(for: headerName, apiKey: apiKey), forHTTPHeaderField: headerName)

        guard transport == .anthropicCompatible else { return }
        if headerName.caseInsensitiveCompare("x-api-key") != .orderedSame {
            request.setValue(rawAPIKeyValue(from: apiKey), forHTTPHeaderField: "x-api-key")
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    }

    private func localModelsURL(endpoint: String) -> URL? {
        let base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "http://localhost:11434"
            : endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: normalizedBase + "/api/tags")
    }

    private func parseLocalModelNames(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }

        return Array(
            Set(models.compactMap { $0["name"] as? String }.filter { !$0.isEmpty })
        )
        .sorted()
    }

    private func parseAPIErrorMessage(from data: Data?) -> String {
        guard let data else { return "Unexpected empty response" }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty {
                return message
            }
            if let error = json["error"] as? String,
               !error.isEmpty {
                return error
            }
            if let detail = json["message"] as? String,
               !detail.isEmpty {
                return detail
            }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Unexpected response" : String(raw.prefix(240))
    }

    private func diagnoseConfiguredAPI(
        endpoint: String,
        apiKey: String,
        apiHeaderName: String,
        model: String,
        requestStyle: APIRequestStyle,
        advancedJSONConfiguration: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        if requestStyle == .json {
            diagnoseAdvancedJSONConfiguredAPI(
                rawConfiguration: advancedJSONConfiguration,
                fallbackEndpoint: endpoint,
                fallbackAPIKey: apiKey,
                fallbackAPIHeaderName: apiHeaderName,
                fallbackModel: model,
                completion: completion
            )
            return
        }
        guard !apiKey.isEmpty else {
            completion(.failure(AIError.noAPIKey))
            return
        }
        if let configurationError = apiConfigurationError(for: apiKey) {
            completion(.failure(configurationError))
            return
        }
        guard let probe = diagnosticProbe(
            endpoint: endpoint,
            apiKey: apiKey,
            apiHeaderName: apiHeaderName,
            model: model
        ) else {
            completion(.failure(AIError.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: probe.request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(AIError.requestFailed(self.requestFailureMessage(for: error))))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(AIError.invalidResponse))
                    return
                }
                guard let data else {
                    completion(.failure(AIError.invalidResponse))
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    completion(.failure(AIError.requestFailed("HTTP \(http.statusCode): \(self.parseAPIErrorMessage(from: data))")))
                    return
                }

                do {
                    let content: String
                    switch probe.transport {
                    case .openAICompatible:
                        content = try self.openAIMessageContent(from: data)
                    case .anthropicCompatible:
                        content = try self.anthropicMessageContent(from: data)
                    }
                    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        completion(.failure(AIError.noContent))
                        return
                    }

                    completion(.success("""
                    API connection successful ✅
                    Protocol: \(self.apiTransportDisplayName(probe.transport))
                    Model: \(probe.model)
                    """))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    private func diagnosticProbe(
        endpoint: String,
        apiKey: String,
        apiHeaderName: String,
        model: String
    ) -> APIDiagnosticProbe? {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return nil }

        let transport = apiTransport(for: endpoint)
        guard let url = apiTransportURL(
            endpoint: endpoint,
            transport: transport,
            openAIPath: "/chat/completions",
            anthropicPath: "/v1/messages",
            defaultBase: transport == .anthropicCompatible
                ? "https://api.minimax.io/anthropic"
                : "https://api.openai.com/v1"
        ) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyConfiguredAPIHeaders(
            to: &request,
            apiKey: apiKey,
            apiHeaderName: apiHeaderName,
            transport: transport
        )
        request.timeoutInterval = 20

        let body: [String: Any]
        switch transport {
        case .openAICompatible:
            var openAIBody: [String: Any] = [
                "model": trimmedModel,
                "messages": [
                    ["role": "system", "content": "You are a connectivity test. Reply with OK."],
                    ["role": "user", "content": "Reply with OK."]
                ],
                "stream": false
            ]
            openAIBody.merge(openAISamplingFields(model: trimmedModel, temperature: 0)) { _, new in new }
            openAIBody.merge(openAICompletionLimitField(model: trimmedModel, maxTokens: 8)) { _, new in new }
            body = openAIBody
        case .anthropicCompatible:
            body = [
                "model": trimmedModel,
                "system": "You are a connectivity test. Reply with OK.",
                "messages": [
                    ["role": "user", "content": "Reply with OK."]
                ],
                "temperature": 0,
                "max_tokens": 8,
                "stream": false
            ]
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return APIDiagnosticProbe(transport: transport, request: request, model: trimmedModel)
    }

    private func openAICompletionLimitField(model: String, maxTokens: Int) -> [String: Any] {
        let key = usesMaxCompletionTokens(for: model) ? "max_completion_tokens" : "max_tokens"
        return [key: maxTokens]
    }

    private func openAISamplingFields(model: String, temperature: Double) -> [String: Any] {
        guard supportsCustomOpenAISampling(for: model) else { return [:] }
        return ["temperature": temperature]
    }

    private func usesMaxCompletionTokens(for model: String) -> Bool {
        let lowercased = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowercased.hasPrefix("gpt-5")
            || lowercased.hasPrefix("o1")
            || lowercased.hasPrefix("o3")
            || lowercased.hasPrefix("o4")
    }

    private func supportsCustomOpenAISampling(for model: String) -> Bool {
        let lowercased = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !lowercased.hasPrefix("gpt-5")
            && !lowercased.hasPrefix("o1")
            && !lowercased.hasPrefix("o3")
            && !lowercased.hasPrefix("o4")
    }

    private func apiConfigurationError(for apiKey: String) -> AIError? {
        let rawKey = rawAPIKeyValue(from: apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = rawKey.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return .requestFailed("API Key looks like an endpoint URL, not a secret key. Re-enter the real provider key in API Key.")
        }
        return nil
    }

    private func openAIMessageContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AIError.requestFailed(message)
        }
        if let error = json["error"] as? String {
            throw AIError.requestFailed(error)
        }
        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        throw AIError.invalidResponse
    }

    private func streamOllama(
        request: URLRequest,
        model: String,
        onStatus: @escaping (String) -> Void,
        onPartial: ((String) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        onStatus("Connecting to Ollama...")
        onStatus("Streaming with \(model)...")

        currentStreamingTask = Task { [weak self] in
            var aggregated = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw AIError.requestFailed("HTTP \(http.statusCode)")
                }

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    guard let content = try self?.ollamaContentChunk(from: trimmed), !content.isEmpty else { continue }
                    aggregated += content
                    if let onPartial {
                        await MainActor.run { onPartial(aggregated) }
                    }
                }

                let finalText = aggregated.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    if finalText.isEmpty {
                        completion(.failure(AIError.noContent))
                    } else {
                        completion(.success(finalText))
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(AIError.cancelled))
                }
            } catch let error as AIError {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(error))
                }
            } catch {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(AIError.requestFailed(self?.requestFailureMessage(for: error) ?? error.localizedDescription)))
                }
            }
        }
    }

    private func streamOpenAICompatible(
        request: URLRequest,
        model: String,
        onStatus: @escaping (String) -> Void,
        onPartial: ((String) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        onStatus("Connecting to API...")
        onStatus("Streaming with \(model)...")

        currentStreamingTask = Task { [weak self] in
            var aggregated = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw AIError.requestFailed("HTTP \(http.statusCode)")
                }

                streamLoop: for try await line in bytes.lines {
                    try Task.checkCancellation()
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let event = try self?.openAIStreamEvent(from: trimmed) ?? .none
                    switch event {
                    case .none:
                        continue
                    case .done:
                        break streamLoop
                    case .content(let content):
                        guard !content.isEmpty else { continue }
                        aggregated += content
                        if let onPartial {
                            await MainActor.run { onPartial(aggregated) }
                        }
                    }
                }

                let finalText = aggregated.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    if finalText.isEmpty {
                        completion(.failure(AIError.noContent))
                    } else {
                        completion(.success(finalText))
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(AIError.cancelled))
                }
            } catch let error as AIError {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(error))
                }
            } catch {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(AIError.requestFailed(self?.requestFailureMessage(for: error) ?? error.localizedDescription)))
                }
            }
        }
    }

    private func streamAnthropicCompatible(
        request: URLRequest,
        model: String,
        onStatus: @escaping (String) -> Void,
        onPartial: ((String) -> Void)?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        onStatus("Connecting to API...")
        onStatus("Streaming with \(model)...")

        currentStreamingTask = Task { [weak self] in
            var aggregated = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AIError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw AIError.requestFailed("HTTP \(http.statusCode)")
                }

                streamLoop: for try await line in bytes.lines {
                    try Task.checkCancellation()
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    let event = try self?.anthropicStreamEvent(from: trimmed) ?? .none
                    switch event {
                    case .none:
                        continue
                    case .done:
                        break streamLoop
                    case .content(let content):
                        guard !content.isEmpty else { continue }
                        aggregated += content
                        if let onPartial {
                            await MainActor.run { onPartial(aggregated) }
                        }
                    }
                }

                let finalText = aggregated.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    if finalText.isEmpty {
                        completion(.failure(AIError.noContent))
                    } else {
                        completion(.success(finalText))
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(AIError.cancelled))
                }
            } catch let error as AIError {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(error))
                }
            } catch {
                await MainActor.run {
                    self?.currentStreamingTask = nil
                    completion(.failure(AIError.requestFailed(self?.requestFailureMessage(for: error) ?? error.localizedDescription)))
                }
            }
        }
    }

    private func ollamaContentChunk(from line: String) throws -> String? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = json["error"] as? String {
            throw AIError.requestFailed(error)
        }
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        if let response = json["response"] as? String {
            return response
        }
        return nil
    }

    private enum OpenAIStreamEvent {
        case content(String)
        case done
        case none
    }

    private enum AnthropicStreamEvent {
        case content(String)
        case done
        case none
    }

    private func openAIStreamEvent(from line: String) throws -> OpenAIStreamEvent {
        let payload: String
        if line.hasPrefix("data:") {
            payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            payload = line
        }

        guard !payload.isEmpty else { return .none }
        if payload == "[DONE]" { return .done }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .none
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AIError.requestFailed(message)
        }
        if let error = json["error"] as? String {
            throw AIError.requestFailed(error)
        }
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first {
            if let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                return .content(content)
            }
            if let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return .content(content)
            }
            if let finishReason = first["finish_reason"] as? String,
               !finishReason.isEmpty {
                return .done
            }
        }
        return .none
    }

    private func anthropicMessageContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AIError.requestFailed(message)
        }
        if let error = json["error"] as? String {
            throw AIError.requestFailed(error)
        }
        if let contentBlocks = json["content"] as? [[String: Any]] {
            return contentBlocks.compactMap { block in
                guard let type = block["type"] as? String, type == "text" else { return nil }
                return block["text"] as? String
            }.joined()
        }
        return ""
    }

    private func anthropicStreamEvent(from line: String) throws -> AnthropicStreamEvent {
        guard line.hasPrefix("data:") else { return .none }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return .none }
        if payload == "[DONE]" { return .done }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .none
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AIError.requestFailed(message)
        }
        if let error = json["error"] as? String {
            throw AIError.requestFailed(error)
        }

        switch json["type"] as? String {
        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String,
               deltaType == "text_delta",
               let text = delta["text"] as? String {
                return .content(text)
            }
            return .none
        case "message_stop":
            return .done
        default:
            return .none
        }
    }
}
