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

    struct InlineAnswerOptions {
        var aiMode: AIMode
        var endpoint: String
        var apiKey: String
        var model: String
        var promptSelection: PromptInjectionSelection

        init(
            aiMode: AIMode,
            endpoint: String,
            apiKey: String,
            model: String,
            promptSelection: PromptInjectionSelection
        ) {
            self.aiMode = aiMode
            self.endpoint = endpoint
            self.apiKey = apiKey
            self.model = model
            self.promptSelection = PromptInjectionConfigurationStore.shared.configuration.normalized(promptSelection)
        }

        init(settings: SettingsManager) {
            self.init(
                aiMode: settings.aiModeEnum,
                endpoint: settings.aiEndpoint,
                apiKey: settings.aiApiKey,
                model: settings.aiModel,
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
            callOllama(endpoint: settings.aiEndpoint,
                       model: settings.aiModel.isEmpty ? "llama3" : settings.aiModel,
                       systemPrompt: systemPrompt, userMessage: userMessage,
                       onStatus: onStatus, completion: completion)
        case .api:
            callOpenAICompatible(endpoint: settings.aiEndpoint,
                                 apiKey: settings.aiApiKey,
                                 model: settings.aiModel.isEmpty ? "gpt-4" : settings.aiModel,
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
            callOpenAICompatible(
                endpoint: options.endpoint,
                apiKey: options.apiKey,
                model: options.model.isEmpty ? "gpt-4" : options.model,
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
            callOpenAICompatible(
                endpoint: options.endpoint,
                apiKey: options.apiKey,
                model: options.model.isEmpty ? "gpt-4" : options.model,
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
            let endpoint = settings.aiEndpoint.isEmpty ? "http://localhost:11434" : settings.aiEndpoint
            guard let url = URL(string: "\(endpoint)/api/tags") else {
                completion(.failure(AIError.invalidURL)); return
            }
            var req = URLRequest(url: url); req.timeoutInterval = 10
            URLSession.shared.dataTask(with: req) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error { completion(.failure(AIError.requestFailed(error.localizedDescription))); return }
                    guard let http = response as? HTTPURLResponse else { completion(.failure(AIError.invalidResponse)); return }
                    if http.statusCode == 200 {
                        var msg = "Connection successful ✅\n"
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let models = json["models"] as? [[String: Any]] {
                            msg += "Models:\n" + models.compactMap { $0["name"] as? String }.map { "  • \($0)" }.joined(separator: "\n")
                        }
                        completion(.success(msg))
                    } else {
                        completion(.failure(AIError.requestFailed("HTTP \(http.statusCode)")))
                    }
                }
            }.resume()
        case .api:
            let endpoint = settings.aiEndpoint.isEmpty ? "https://api.openai.com/v1" : settings.aiEndpoint
            guard let url = URL(string: "\(endpoint)/models") else { completion(.failure(AIError.invalidURL)); return }
            guard !settings.aiApiKey.isEmpty else { completion(.failure(AIError.noAPIKey)); return }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(settings.aiApiKey)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 10
            URLSession.shared.dataTask(with: req) { _, response, error in
                DispatchQueue.main.async {
                    if let error = error { completion(.failure(AIError.requestFailed(error.localizedDescription))); return }
                    guard let http = response as? HTTPURLResponse else { completion(.failure(AIError.invalidResponse)); return }
                    if http.statusCode == 200 { completion(.success("API connection successful ✅")) }
                    else { completion(.failure(AIError.requestFailed("HTTP \(http.statusCode)"))) }
                }
            }.resume()
        }
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
                if let error = error { completion(.failure(AIError.requestFailed(error.localizedDescription))); return }
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

    // MARK: - OpenAI-compatible

    private func callOpenAICompatible(endpoint: String, apiKey: String, model: String,
                                      systemPrompt: String, userMessage: String,
                                      temperature: Double = 0.7,
                                      maxTokens: Int = 1024,
                                      streamResponse: Bool = false,
                                      onStatus: @escaping (String) -> Void,
                                      onPartial: ((String) -> Void)? = nil,
                                      completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else { completion(.failure(AIError.noAPIKey)); return }
        let base = endpoint.isEmpty ? "https://api.openai.com/v1" : endpoint
        guard let url = URL(string: "\(base)/chat/completions") else { completion(.failure(AIError.invalidURL)); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 180
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": userMessage]],
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": streamResponse
        ]
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
                if let error = error { completion(.failure(AIError.requestFailed(error.localizedDescription))); return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let msg = choices.first?["message"] as? [String: Any],
                      let content = msg["content"] as? String else {
                    let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "?"
                    completion(.failure(AIError.requestFailed("Unexpected: \(raw.prefix(200))"))); return
                }
                completion(.success(content))
            }
        }
        currentTask = task
        task?.resume()
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
                    completion(.failure(AIError.requestFailed(error.localizedDescription)))
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
                    completion(.failure(AIError.requestFailed(error.localizedDescription)))
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
}
