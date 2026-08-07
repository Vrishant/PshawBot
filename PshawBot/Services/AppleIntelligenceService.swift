// AppleIntelligenceService.swift
// PshawBot
//
// Apple Intelligence (FoundationModels) backend.
// Requires macOS 26+ with Apple Intelligence enabled on the device.
//
// Design notes:
// - A single LanguageModelSession is reused across turns; the framework
//   maintains the transcript automatically, so we do NOT replay history
//   manually like the old Gemini implementation.
// - clearChat() creates a fresh session, which discards the prior context.
// - If Apple Intelligence is unavailable, a system message is shown in the
//   chat instead of crashing.

import Foundation
import FoundationModels
import OSLog

@available(macOS 26.0, *)
@MainActor
final class AppleIntelligenceService: ObservableObject {

    // MARK: - Published

    @Published var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false

    // MARK: - Private

    private let logger = Logger(subsystem: "com.pshawbot", category: "AppleIntelligenceService")

    /// The active session. Replaced on clearChat().
    private var session: LanguageModelSession

    private let systemInstruction = """
        You are a concise, expert screen-intelligence assistant embedded in a macOS desktop app. \
        The app observes the user's screen and extracts code, UI layouts, and text. \
        When given code, analyse it clearly: explain the approach, state the time and space \
        complexity, and suggest improvements. Answer follow-up questions directly and briefly. \
        Format code in markdown code blocks.
        """

    // MARK: - Init

    init() {
        self.session = LanguageModelSession(
            instructions: systemInstruction
        )
        checkAvailability()
    }

    // MARK: - Availability

    private func checkAvailability() {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            logger.info("Apple Intelligence: available")
        case .unavailable(let reason):
            let msg: String
            switch reason {
            case .deviceNotEligible:
                msg = "⚠️ Apple Intelligence requires an eligible Apple Silicon device."
            case .appleIntelligenceNotEnabled:
                msg = "⚠️ Apple Intelligence is not enabled. Go to System Settings → Apple Intelligence & Siri to enable it."
            @unknown default:
                msg = "⚠️ Apple Intelligence is not available on this device."
            }
            logger.warning("Apple Intelligence unavailable: \(msg)")
            messages.append(ChatMessage(role: .system, text: msg))
        @unknown default:
            logger.warning("Apple Intelligence: unknown availability state")
        }
    }

    // MARK: - AIService Implementation

    /// Sends the extracted code with an optional user question.
    func sendCode(_ code: String, language: String?, userPrompt: String? = nil) async {
        let lang = language ?? "C++"
        let prompt: String
        if let custom = userPrompt, !custom.isEmpty {
            prompt = """
            Here is a \(lang) code snippet captured from the screen:

            ```\(lang.lowercased())
            \(code)
            ```

            \(custom)
            """
        } else {
            prompt = """
            Here is a \(lang) code snippet captured from the screen. Please analyse it:
            1. Explain the approach
            2. State the time and space complexity
            3. Suggest any optimisations

            ```\(lang.lowercased())
            \(code)
            ```
            """
        }

        messages.append(ChatMessage(role: .user, text: userPrompt ?? "Analyse this \(lang) code"))
        await respond(to: prompt)
    }

    /// Sends a follow-up message. The session retains prior context automatically.
    func sendFollowUp(_ text: String, codeContext: String?, language: String?) async {
        messages.append(ChatMessage(role: .user, text: text))

        // If this is a fresh session with code context, prepend the code so the
        // model has it — this mirrors the old Gemini multi-turn preamble.
        var fullPrompt = text
        if messages.count == 1, let code = codeContext {
            let lang = language ?? "C++"
            fullPrompt = """
            Context — \(lang) code captured from the screen:

            ```\(lang.lowercased())
            \(code)
            ```

            \(text)
            """
        }

        await respond(to: fullPrompt)
    }

    /// Resets conversation history and creates a fresh session.
    func clearChat() {
        messages.removeAll()
        session = LanguageModelSession(
            instructions: systemInstruction
        )
        logger.debug("Chat cleared, new session created")
    }

    // MARK: - Private

    private func respond(to prompt: String) async {
        isLoading = true
        defer { isLoading = false }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            logger.warning("respond(to:) called while model unavailable")
            messages.append(ChatMessage(role: .system, text: "❌ Apple Intelligence is not available. Check System Settings."))
            return
        }

        do {
            logger.debug("Sending prompt (\(prompt.count) chars) to Apple Intelligence")
            print("\n========== AI PROMPT ==========")
            print(prompt)
            print("===============================\n")

            let response = try await session.respond(to: prompt)
            let text = response.content
            
            logger.debug("Received response (\(text.count) chars)")
            print("\n========= AI RESPONSE =========")
            print(text)
            print("===============================\n")

            messages.append(ChatMessage(role: .model, text: text))
        } catch {
            logger.error("Apple Intelligence error: \(error.localizedDescription)")
            messages.append(ChatMessage(role: .system, text: "❌ Error: \(error.localizedDescription)"))
        }
    }
}
