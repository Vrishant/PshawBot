// AIServiceProtocol.swift
// PshawBot
//
// Provider-agnostic chat types and protocol.
// Any AI backend (Apple Intelligence, Gemini, Claude, Ollama…) should
// conform to AIService to be usable by ChatView and LivePreviewView.

import Foundation

// MARK: - ChatMessage

/// A single message in a conversation, independent of the AI provider.
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

    enum Role: String {
        case user
        case model
        case system
    }
}

// MARK: - AIService

/// The contract every AI backend must satisfy.
///
/// Keep this protocol thin — it represents exactly what the UI needs.
/// Do NOT add provider-specific concepts (API keys, models, endpoints) here.
///
/// Usage:
///   - Conform with `@MainActor final class MyProvider: ObservableObject`
///   - Publish `messages` and `isLoading` via `@Published`
///   - Pass instances as `some AIService` or via a concrete type where
///     SwiftUI's ObservableObject machinery requires it.
protocol AIService: AnyObject, ObservableObject {
    /// Full conversation history, including system notices.
    var messages: [ChatMessage] { get }

    /// True while an LLM request is in-flight.
    var isLoading: Bool { get }

    /// Sends an initial code + optional user question.
    /// Appends both the user turn and the model response to `messages`.
    func sendCode(_ code: String, language: String?, userPrompt: String?) async

    /// Sends a follow-up question, keeping prior context.
    func sendFollowUp(_ text: String, codeContext: String?, language: String?) async

    /// Resets the conversation state.
    func clearChat()
}
