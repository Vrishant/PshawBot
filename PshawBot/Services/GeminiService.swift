// GeminiService.swift
// PshawBot
//
// REST client for Google's Gemini API.
// Kept as a future opt-in provider; not the default backend.
// The default AI backend is AppleIntelligenceService.

import Foundation
import OSLog

// MARK: - GeminiMessage

/// Backward-compatibility alias. All chat UI now uses `ChatMessage` directly.
typealias GeminiMessage = ChatMessage

// MARK: - GeminiService

@MainActor
final class GeminiService: ObservableObject {
    
    private let logger = Logger(subsystem: "com.pshawbot", category: "GeminiService (inactive)")
    
    @Published var messages: [GeminiMessage] = []
    @Published var isLoading: Bool = false
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "gemini_api_key")
        }
    }
    
    private let model = "gemini-2.5-flash"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    
    init() {
        self.apiKey = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
    }
    
    // MARK: - API
    
    /// Sends the extracted code with a prompt to Gemini and appends the response.
    func sendCode(_ code: String, language: String?, userPrompt: String? = nil) async {
        guard !apiKey.isEmpty else {
            messages.append(GeminiMessage(role: .system, text: "⚠️ No API key set. Enter your Gemini API key in the field above."))
            return
        }
        
        // Build the prompt
        let lang = language ?? "C++"
        let prompt: String
        if let custom = userPrompt, !custom.isEmpty {
            prompt = """
            Here is a \(lang) LeetCode solution:
            
            ```\(lang.lowercased())
            \(code)
            ```
            
            \(custom)
            """
        } else {
            prompt = """
            Here is a \(lang) LeetCode solution. Please analyze it:
            1. Explain the approach
            2. State the time and space complexity
            3. Suggest any optimizations
            
            ```\(lang.lowercased())
            \(code)
            ```
            """
        }
        
        // Add user message to chat
        messages.append(GeminiMessage(role: .user, text: userPrompt ?? "Analyze this \(lang) code"))
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response = try await callGemini(prompt: prompt)
            messages.append(GeminiMessage(role: .model, text: response))
        } catch {
            logger.error("Gemini API error: \(error.localizedDescription)")
            messages.append(GeminiMessage(role: .system, text: "❌ Error: \(error.localizedDescription)"))
        }
    }
    
    /// Sends a follow-up message using conversation history.
    func sendFollowUp(_ text: String, codeContext: String?, language: String?) async {
        guard !apiKey.isEmpty else {
            messages.append(GeminiMessage(role: .system, text: "⚠️ No API key set."))
            return
        }
        
        messages.append(GeminiMessage(role: .user, text: text))
        isLoading = true
        defer { isLoading = false }
        
        // Build conversation contents for multi-turn
        var contents: [[String: Any]] = []
        
        // Add code context as the first turn if available
        if let code = codeContext {
            let lang = language ?? "C++"
            contents.append([
                "role": "user",
                "parts": [["text": "Here is a \(lang) LeetCode solution:\n```\(lang.lowercased())\n\(code)\n```"]]
            ])
            contents.append([
                "role": "model",
                "parts": [["text": "I see the code. How can I help?"]]
            ])
        }
        
        // Add conversation history
        for msg in messages where msg.role != .system {
            contents.append([
                "role": msg.role.rawValue,
                "parts": [["text": msg.text]]
            ])
        }
        
        do {
            let response = try await callGemini(contents: contents)
            messages.append(GeminiMessage(role: .model, text: response))
        } catch {
            logger.error("Gemini API error: \(error.localizedDescription)")
            messages.append(GeminiMessage(role: .system, text: "❌ Error: \(error.localizedDescription)"))
        }
    }
    
    /// Clears conversation history.
    func clearChat() {
        messages.removeAll()
    }
    
    // MARK: - Private
    
    /// Single-turn API call.
    private func callGemini(prompt: String) async throws -> String {
        let contents: [[String: Any]] = [
            [
                "role": "user",
                "parts": [["text": prompt]]
            ]
        ]
        return try await callGemini(contents: contents)
    }
    
    /// Multi-turn API call.
    private func callGemini(contents: [[String: Any]]) async throws -> String {
        let urlString = "\(baseURL)/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 4096,
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("🤖 [Gemini] Sending request to \(model)...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Gemini HTTP \(httpResponse.statusCode): \(errorBody)")
            print("❌ [Gemini] Error \(httpResponse.statusCode): \(errorBody)")
            throw GeminiError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }
        
        // Parse the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            print("❌ [Gemini] Failed to parse response JSON")
            throw GeminiError.parseError
        }
        
        print("✅ [Gemini] Received response (\(text.count) characters):\n\(text)\n-----------------------------------")
        return text
    }
}

// MARK: - GeminiError

enum GeminiError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code, let body):
            if code == 400 { return "Bad request — check your API key" }
            if code == 403 { return "API key is invalid or unauthorized" }
            if code == 429 { return "Rate limit exceeded — try again in a moment" }
            return "HTTP \(code): \(body.prefix(200))"
        case .parseError: return "Could not parse Gemini response"
        }
    }
}
