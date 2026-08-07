// CodeLexer.swift
// PshawBot
//
// A lightweight C++ lexer that extracts structured code from noisy OCR output.
// Instead of relying on spatial bounding boxes, it uses bracket-depth tracking
// to find the complete code block starting from "class Solution".
//
// Strategy:
//   1. Scan all OCR text for the anchor line ("class Solution {")
//   2. From there, track brace depth { +1, } -1
//   3. When depth returns to 0, the class is complete
//   4. Strip any non-code noise lines that leaked through OCR

import Foundation
import OSLog

// MARK: - CodeLexer

/// Extracts clean, complete code from noisy OCR text using structural parsing.
struct CodeLexer {
    
    private static let logger = Logger(subsystem: "com.pshawbot", category: "CodeLexer")
    
    // MARK: - Noise Patterns
    
    /// UI labels and chrome text that OCR picks up from around the code editor.
    /// These are never valid C++ code.
    private static let noisePatterns: Set<String> = [
        "code", "auto", "saved", "submit", "testcase", "test result",
        "case 1", "case 2", "case 3", "online", "source", "submissions",
        "description", "editorial", "solutions", "companies", "topics",
        "hint", "copy code", "dark space", "cdn media", "about",
        "daily question", "hard", "medium", "easy", "example",
        "input:", "output:", "explanation:", "constraints:",
        "note:", "follow up:", "follow-up:",
    ]
    
    /// Substrings that identify a line as definitely UI chrome, not code.
    private static let noiseSubstrings: [String] = [
        "© ", "• ", "‹/›", "</> Source", "Ln ", "Col ",
        "Online", "PES ", "NGC ", "Webb", "TKDL",
        "Full Stack", "Course:",
    ]
    
    // MARK: - API
    
    /// Takes raw OCR text (potentially noisy) and extracts clean C++ code.
    ///
    /// - Parameter rawText: The concatenated OCR output from the code panel region.
    /// - Returns: Clean, parseable C++ code, or nil if no valid code block was found.
    static func extractCode(from rawText: String) -> String? {
        let lines = rawText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        
        // Phase 1: Strip noise lines
        let cleanedLines = lines.filter { !isNoiseLine($0) }
        
        logger.debug("CodeLexer: \(lines.count) raw lines → \(cleanedLines.count) after noise removal")
        
        // Phase 2: Find the anchor — "class Solution"
        guard let anchorIndex = findAnchor(in: cleanedLines) else {
            logger.info("CodeLexer: No anchor found (class Solution / public class)")
            // Fall back to returning all cleaned non-empty lines
            let fallback = cleanedLines.filter { !$0.isEmpty }.joined(separator: "\n")
            return fallback.isEmpty ? nil : fallback
        }
        
        // Phase 3: Extract the complete code block using bracket matching
        let codeBlock = extractBracketBlock(from: cleanedLines, startingAt: anchorIndex)
        
        logger.info("CodeLexer: Extracted \(codeBlock.count) lines of code")
        
        let result = codeBlock.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }
    
    /// Takes individual OCR text blocks (with spatial info) and extracts code.
    /// This is the main entry point — it handles line-number stripping and
    /// reassembly from fragmented OCR blocks.
    ///
    /// - Parameter blocks: The RecognizedText blocks from the code panel.
    /// - Returns: Clean C++ code string.
    static func extractCode(from blocks: [RecognizedText]) -> String? {
        // Sort blocks by Y position (top to bottom), then X (left to right)
        let sorted = blocks.sorted { a, b in
            if abs(a.bounds.midY - b.bounds.midY) < 10 {
                return a.bounds.midX < b.bounds.midX
            }
            return a.bounds.midY < b.bounds.midY
        }
        
        // Group blocks into lines based on Y proximity
        var lines: [String] = []
        var currentLineBlocks: [RecognizedText] = []
        var currentLineY: CGFloat = -9999
        
        for block in sorted {
            if abs(block.bounds.midY - currentLineY) > 12 {
                // New line
                if !currentLineBlocks.isEmpty {
                    let lineText = currentLineBlocks.map { $0.string }.joined(separator: " ")
                    lines.append(lineText)
                }
                currentLineBlocks = [block]
                currentLineY = block.bounds.midY
            } else {
                // Same line
                currentLineBlocks.append(block)
            }
        }
        // Flush last line
        if !currentLineBlocks.isEmpty {
            let lineText = currentLineBlocks.map { $0.string }.joined(separator: " ")
            lines.append(lineText)
        }
        
        // Strip leading line numbers (LeetCode shows "1", "2", "3" etc.)
        let stripped = lines.map { stripLineNumber($0) }
        
        // Rejoin and run the lexer
        let rawText = stripped.joined(separator: "\n")
        return extractCode(from: rawText)
    }
    
    // MARK: - Noise Detection
    
    /// Returns true if a line is clearly UI chrome and not code.
    private static func isNoiseLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        
        // Exact matches (case-insensitive)
        if noisePatterns.contains(trimmed.lowercased()) {
            return true
        }
        
        // Substring matches
        for noise in noiseSubstrings {
            if trimmed.contains(noise) { return true }
        }
        
        // Pure numbers that are standalone (like "98", "2065") are noise
        if Int(trimmed) != nil && trimmed.count <= 5 {
            return true
        }
        
        // Lines that are just a single word and don't look like code
        // (e.g. "Submit", "Saved", "Code")
        let words = trimmed.split(separator: " ")
        if words.count == 1 {
            let word = String(words[0])
            // Single words that are valid C++ are okay
            let validSingleWords: Set<String> = [
                "{", "}", "};", "return", "break", "continue", "else",
                "public:", "private:", "protected:", "default:",
            ]
            if validSingleWords.contains(word) { return false }
            
            // If it starts with uppercase and has no code characters, likely UI
            if word.first?.isUppercase == true &&
               !word.contains("{") && !word.contains("}") &&
               !word.contains("(") && !word.contains(";") &&
               !word.contains("::") {
                // Check if it's a type name used in code
                let codeTypes: Set<String> = [
                    "Solution", "TreeNode", "ListNode", "Node", "String",
                ]
                if !codeTypes.contains(word) {
                    return true
                }
            }
        }
        
        // Lines with "v" alone (language selector dropdown arrow)
        if trimmed == "v" || trimmed == "A" || trimmed == "+" { return true }
        
        return false
    }
    
    // MARK: - Anchor Detection
    
    /// Finds the line index of the code anchor (class definition).
    private static func findAnchor(in lines: [String]) -> Int? {
        // Priority 1: "class Solution"
        if let idx = lines.firstIndex(where: { $0.contains("class Solution") || $0.contains("class solution") }) {
            return idx
        }
        
        // Priority 2: "public class"
        if let idx = lines.firstIndex(where: { $0.contains("public class") }) {
            return idx
        }
        
        // Priority 3: "struct Solution"
        if let idx = lines.firstIndex(where: { $0.contains("struct Solution") }) {
            return idx
        }
        
        // Priority 4: First line containing an opening brace with a keyword
        if let idx = lines.firstIndex(where: { line in
            line.contains("{") && (
                line.contains("class ") || line.contains("struct ") ||
                line.contains("def ") || line.contains("func ")
            )
        }) {
            return idx
        }
        
        return nil
    }
    
    // MARK: - Bracket Matching
    
    /// Starting from `startIndex`, extracts all lines until the bracket depth
    /// returns to zero. This captures the complete class body.
    private static func extractBracketBlock(from lines: [String], startingAt startIndex: Int) -> [String] {
        var result: [String] = []
        var braceDepth = 0
        var started = false // Have we seen the first `{`?
        
        for i in startIndex..<lines.count {
            let line = lines[i]
            
            // Count braces on this line
            for char in line {
                if char == "{" {
                    braceDepth += 1
                    started = true
                } else if char == "}" {
                    braceDepth -= 1
                }
            }
            
            // Skip noise that leaked through
            if isNoiseLine(line) && !line.contains("{") && !line.contains("}") {
                continue
            }
            
            result.append(line)
            
            // If we've opened at least one brace and returned to 0, we're done
            if started && braceDepth <= 0 {
                break
            }
        }
        
        // If we never found a closing brace, still return what we have
        if !started {
            logger.warning("CodeLexer: No opening brace found from anchor")
        } else if braceDepth > 0 {
            logger.warning("CodeLexer: Unclosed braces (depth=\(braceDepth)) — code may be truncated on screen")
        }
        
        return result
    }
    
    // MARK: - Line Number Stripping
    
    /// Removes leading line numbers that LeetCode prepends (e.g. "1 class Solution {" → "class Solution {").
    private static func stripLineNumber(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Match pattern: starts with 1+ digits, then whitespace, then code
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let _ = Int(String(parts[0])) else {
            return line
        }
        
        // Verify the rest looks like code (not a pure number like "2065 Online")
        let rest = String(parts[1])
        let codeIndicators = ["{", "}", "(", ")", ";", "class ", "int ", "string ", "void ",
                              "return", "public", "private", "//", "/*", "if ", "for ", "while "]
        let looksLikeCode = codeIndicators.contains(where: { rest.lowercased().contains($0.lowercased()) })
        
        if looksLikeCode || rest.trimmingCharacters(in: .whitespaces) == "}" || rest.trimmingCharacters(in: .whitespaces) == "};" {
            return rest
        }
        
        return line
    }
}

// MARK: - RecognizedText (import for type reference)

// RecognizedText is already defined in OCREngine.swift, we just reference it here.
