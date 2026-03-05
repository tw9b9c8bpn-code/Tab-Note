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
    private init() {}

    enum AIError: LocalizedError {
        case noEndpoint, invalidURL, noAPIKey
        case requestFailed(String)
        case invalidResponse, noContent

        var errorDescription: String? {
            switch self {
            case .noEndpoint: return "No AI endpoint configured"
            case .invalidURL: return "Invalid endpoint URL"
            case .noAPIKey: return "No API key configured"
            case .requestFailed(let msg): return "Request failed: \(msg)"
            case .invalidResponse: return "Invalid response from AI"
            case .noContent: return "No content in AI response"
            }
        }
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
                            onStatus: @escaping (String) -> Void,
                            completion: @escaping (Result<String, Error>) -> Void) {
        let base = endpoint.isEmpty ? "http://localhost:11434" : endpoint
        guard let url = URL(string: "\(base)/api/chat") else { completion(.failure(AIError.invalidURL)); return }
        onStatus("Connecting to Ollama...")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 180
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": userMessage]],
            "stream": false
        ])
        onStatus("Generating with \(model)...")
        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
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
        }.resume()
    }

    // MARK: - OpenAI-compatible

    private func callOpenAICompatible(endpoint: String, apiKey: String, model: String,
                                      systemPrompt: String, userMessage: String,
                                      onStatus: @escaping (String) -> Void,
                                      completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else { completion(.failure(AIError.noAPIKey)); return }
        let base = endpoint.isEmpty ? "https://api.openai.com/v1" : endpoint
        guard let url = URL(string: "\(base)/chat/completions") else { completion(.failure(AIError.invalidURL)); return }
        onStatus("Connecting to API...")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 180
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": userMessage]],
            "temperature": 0.7, "max_tokens": 1024
        ])
        onStatus("Generating with \(model)...")
        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
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
        }.resume()
    }
}
