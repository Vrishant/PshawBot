// ChatView.swift
// PshawBot
//
// A chat interface for talking to the on-device AI about the extracted code.

import SwiftUI

@available(macOS 26.0, *)
struct ChatView: View {
    @ObservedObject var aiService: AppleIntelligenceService
    let codeContext: String?
    let language: String?
    var onClose: (() -> Void)? = nil

    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                Text("Apple Intelligence")
                    .font(.headline)

                Spacer()

                Button(action: { aiService.clearChat() }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .help("Clear Chat")
                .padding(.trailing, 8)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Chat Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if aiService.messages.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                Text("Ask Apple Intelligence to explain, optimise, or debug the extracted code.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 40)
                        }

                        ForEach(aiService.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }

                        if aiService.isLoading {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding()
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: aiService.messages.count) {
                    if let last = aiService.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: aiService.isLoading) {
                    if aiService.isLoading {
                        withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input Area
            HStack(spacing: 12) {
                TextField("Ask something…", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                    .onSubmit { sendMessage() }

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiService.isLoading)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        Task {
            if aiService.messages.isEmpty || aiService.messages.allSatisfy({ $0.role == .system }) {
                // First real message — include the full code context
                await aiService.sendCode(codeContext ?? "", language: language, userPrompt: text)
            } else {
                await aiService.sendFollowUp(text, codeContext: codeContext, language: language)
            }
        }
    }
}

// MARK: - MessageRow

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "You" : (message.role == .system ? "System" : "Apple Intelligence"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Super basic markdown parsing for code blocks
                if message.text.contains("```") {
                    CodeBlockText(text: message.text)
                } else {
                    Text(LocalizedStringKey(message.text))
                        .font(.system(.body))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.role != .user { Spacer() }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return .blue.opacity(0.8)
        case .model: return Color(NSColor.textBackgroundColor).opacity(0.8)
        case .system: return .red.opacity(0.2)
        }
    }
}

// MARK: - Basic Markdown Code Block Parser

struct CodeBlockText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseBlocks(text), id: \.self) { block in
                if block.isCode {
                    Text(block.content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(LocalizedStringKey(block.content))
                        .font(.system(.body))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    struct Block: Hashable {
        let isCode: Bool
        let content: String
    }

    private func parseBlocks(_ text: String) -> [Block] {
        let components = text.components(separatedBy: "```")
        var blocks: [Block] = []
        for (index, component) in components.enumerated() {
            let isCode = index % 2 != 0
            if isCode {
                // Strip the language identifier (e.g. "cpp\n")
                var content = component.trimmingCharacters(in: .whitespacesAndNewlines)
                if let firstNewline = content.firstIndex(of: "\n") {
                    let firstLine = content[..<firstNewline]
                    if !firstLine.contains(" ") {
                        content = String(content[content.index(after: firstNewline)...])
                    }
                }
                blocks.append(Block(isCode: true, content: content))
            } else {
                let content = component.trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    blocks.append(Block(isCode: false, content: content))
                }
            }
        }
        return blocks
    }
}
