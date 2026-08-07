// CodePanelDetector.swift
// PshawBot
//
// Detects the coding panel on screen using multi-signal heuristics:
//   1. Code-like OCR text patterns (keywords, brackets, line numbers)
//   2. Layout geometry (right-half, vertical panel, large area)
//   3. Monochromatic background (dark code editors)
//
// This works for ANY app – native IDEs (Xcode, VSCode) AND browser-based
// editors (LeetCode, CodePen, Replit, etc.) since it operates on pixels + OCR,
// not the AX tree.

import Foundation
import CoreGraphics
import Vision
import OSLog

// MARK: - DetectedCodePanel

/// The result of a code panel detection pass.
struct DetectedCodePanel: Sendable {
    /// The bounding rect of the code editor region in screen coordinates.
    let bounds: CGRect
    
    /// Confidence 0–1 that this is actually a code panel.
    let confidence: Float
    
    /// The raw extracted code text, in reading order.
    let codeText: String
    
    /// Detected programming language (best guess).
    let language: String?
    
    /// Individual lines of code, in order.
    var codeLines: [String] {
        codeText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - CodePanelDetector

/// Finds the code-editing region of the current screen snapshot using
/// text-pattern analysis and layout heuristics.
actor CodePanelDetector {
    
    private let logger = Logger(subsystem: "com.pshawbot", category: "CodePanelDetector")
    
    // MARK: - Keyword Sets
    
    /// Programming keywords that strongly indicate a code region.
    private static let codeKeywords: Set<String> = [
        // C / C++ / Java / Swift / Kotlin / Dart
        "int", "void", "return", "class", "public", "private", "protected",
        "static", "final", "const", "let", "var", "func", "fun", "def",
        "if", "else", "for", "while", "do", "switch", "case", "break",
        "continue", "new", "delete", "nullptr", "null", "nil", "true", "false",
        "import", "include", "namespace", "struct", "enum", "protocol",
        "interface", "extends", "implements", "override", "virtual",
        "try", "catch", "throw", "throws", "async", "await", "auto",
        // Python
        "def", "lambda", "yield", "pass", "with", "as", "from",
        // JS/TS
        "function", "const", "let", "var", "=>", "===", "!==",
        // Common patterns
        "Solution", "main", "vector", "string", "bool", "char",
        "ArrayList", "HashMap", "TreeMap", "List", "Map", "Set",
    ]
    
    /// Patterns in text that strongly indicate code (regex-like literals).
    private static let codePatterns: [String] = [
        "{", "}", "()", ");", "//", "/*", "*/", "->", "::", "++",
        "--", "&&", "||", "!=", "==", ">=", "<=", "#include", "#define",
    ]
    
    // MARK: - API
    
    /// Analyses a screen image and its OCR results to find the primary code panel.
    ///
    /// - Parameters:
    ///   - image: The full screen CGImage.
    ///   - ocrBlocks: OCR text blocks already extracted by `OCREngine`.
    ///   - displayBounds: The screen bounds in points.
    /// - Returns: A `DetectedCodePanel` if one is found with reasonable confidence.
    func detect(
        in image: CGImage,
        ocrBlocks: [RecognizedText],
        displayBounds: CGRect
    ) async -> DetectedCodePanel? {
        
        guard !ocrBlocks.isEmpty else { return nil }
        
        // 1. Score each OCR block for "code-likeness"
        let scoredBlocks = ocrBlocks.map { block -> (RecognizedText, Float) in
            let score = codeScore(for: block.string)
            return (block, score)
        }
        
        // 2. Find the spatial cluster with the highest aggregate code score.
        //    We grid the screen into columns and score each column.
        let codeyBlocks = scoredBlocks.filter { $0.1 > 0.1 }
        guard !codeyBlocks.isEmpty else {
            logger.debug("No code-like text blocks found")
            return nil
        }
        
        // 3. Find the bounding rect that encloses the highest-scoring cluster.
        guard let panelRect = findCodePanelRect(
            from: codeyBlocks.map { $0.0 },
            allBlocks: ocrBlocks,
            displayBounds: displayBounds
        ) else {
            logger.debug("Could not compute code panel rect")
            return nil
        }
        
        // 4. Gather ALL OCR blocks inside the panel rect.
        //    We're generous here — the CodeLexer will sort out noise.
        let insideBlocks = ocrBlocks.filter { block in
            panelRect.intersects(block.bounds) &&
            block.bounds.midX >= panelRect.minX - 40
        }
        
        // 5. Run the CodeLexer to structurally extract clean code.
        //    This uses bracket-depth tracking from "class Solution" to capture
        //    the complete code block, stripping UI noise.
        let lexedCode: String
        if let extracted = CodeLexer.extractCode(from: insideBlocks) {
            lexedCode = extracted
        } else {
            // Fallback: raw join (shouldn't happen if anchor exists)
            let sorted = insideBlocks.sorted {
                if abs($0.bounds.midY - $1.bounds.midY) < 8 {
                    return $0.bounds.midX < $1.bounds.midX
                }
                return $0.bounds.midY < $1.bounds.midY
            }
            lexedCode = sorted.map { $0.string }.joined(separator: "\n")
        }
        
        // 6. Compute overall confidence
        let avgScore = codeyBlocks.reduce(0) { $0 + $1.1 } / Float(codeyBlocks.count)
        let coverageFraction = Float(codeyBlocks.count) / Float(max(ocrBlocks.count, 1))
        let confidence = min(1.0, avgScore * 0.6 + coverageFraction * 0.4)
        
        // 7. Detect language
        let detectedLanguage = detectLanguage(in: lexedCode)
        
        logger.info("Code panel detected: \(String(describing: panelRect)) confidence=\(confidence) lang=\(detectedLanguage ?? "unknown")")
        
        return DetectedCodePanel(
            bounds: panelRect,
            confidence: confidence,
            codeText: lexedCode,
            language: detectedLanguage
        )
    }
    
    // MARK: - Scoring
    
    /// Returns a 0–1 score for how code-like a text string looks.
    private func codeScore(for text: String) -> Float {
        var score: Float = 0
        let words = text.split(separator: " ").map(String.init)
        
        // Keyword hits
        let keywordHits = words.filter { CodePanelDetector.codeKeywords.contains($0.lowercased()) }.count
        score += Float(keywordHits) * 0.15
        
        // Pattern hits
        for pattern in CodePanelDetector.codePatterns {
            if text.contains(pattern) { score += 0.1 }
        }
        
        // Line-number prefix (e.g. "1 class Solution {")
        if let first = words.first, Int(first) != nil {
            score += 0.2
        }
        
        // High ratio of non-letter characters (operators, brackets)
        let nonAlphaCount = text.filter { !$0.isLetter && !$0.isWhitespace }.count
        let ratio = Float(nonAlphaCount) / Float(max(text.count, 1))
        score += ratio * 0.3
        
        return min(1.0, score)
    }
    
    // MARK: - Geometry
    
    /// Finds the rectangular region that best encompasses the code blocks.
    /// Uses a column-based voting approach to handle LeetCode's split-panel layout.
    private func findCodePanelRect(
        from codeBlocks: [RecognizedText],
        allBlocks: [RecognizedText],
        displayBounds: CGRect
    ) -> CGRect? {
        guard !codeBlocks.isEmpty else { return nil }
        
        // Find an anchor block, prioritizing LeetCode's standard class definitions
        let anchorBlock = codeBlocks.first { block in
            block.string.contains("class Solution") ||
            block.string.contains("public class") ||
            block.string.contains("def ")
        }
        
        let anchorX: CGFloat
        if let anchor = anchorBlock {
            anchorX = anchor.bounds.minX
            logger.debug("Anchoring column using block: '\(anchor.string)'")
        } else {
            // Fallback: Median X position
            let sortedByX = codeBlocks.sorted { $0.bounds.minX < $1.bounds.minX }
            anchorX = sortedByX[sortedByX.count / 2].bounds.minX
            logger.debug("Anchoring column using median X: \(anchorX)")
        }
        
        // Get all code blocks on the same "side" as the anchor
        // We use minX to group them vertically, as code lines are left-aligned
        let sameColumnBlocks = codeBlocks.filter { block in
            abs(block.bounds.minX - anchorX) < displayBounds.width * 0.25
        }
        
        // Sort them by vertical position to find contiguous code lines
        let sortedColumnBlocks = sameColumnBlocks.sorted { $0.bounds.midY < $1.bounds.midY }
        
        // Find our anchor in the sorted list
        let anchorString = anchorBlock?.string ?? sortedColumnBlocks[sortedColumnBlocks.count / 2].string
        guard let anchorIndex = sortedColumnBlocks.firstIndex(where: { $0.string == anchorString }) else { return nil }
        
        var validBlocks: [RecognizedText] = [sortedColumnBlocks[anchorIndex]]
        let maxVerticalGap: CGFloat = 150.0 // Increased to bridge multiple empty blank lines in code
        
        // Traverse upwards from anchor
        var currentY = sortedColumnBlocks[anchorIndex].bounds.minY
        for i in (0..<anchorIndex).reversed() {
            let block = sortedColumnBlocks[i]
            let gap = currentY - block.bounds.maxY
            if gap > maxVerticalGap { break }
            // Stop at obvious header UI
            let lower = block.string.lowercased()
            if lower == "code" || lower.contains("c++") || lower == "auto" { break }
            
            validBlocks.append(block)
            currentY = block.bounds.minY
        }
        
        // Traverse downwards from anchor
        currentY = sortedColumnBlocks[anchorIndex].bounds.maxY
        for i in (anchorIndex + 1)..<sortedColumnBlocks.count {
            let block = sortedColumnBlocks[i]
            let gap = block.bounds.minY - currentY
            if gap > maxVerticalGap { break }
            // Stop at obvious footer UI
            let lower = block.string.lowercased()
            if lower.contains("testcase") || lower == "saved" || lower.contains("test result") || lower.contains("online") || lower == "source" { break }
            
            validBlocks.append(block)
            currentY = block.bounds.maxY
        }
        
        // Compute bounding rect strictly around valid code blocks
        let minX = validBlocks.map { $0.bounds.minX }.min()! - 35 // Extra padding for line numbers
        let minY = validBlocks.map { $0.bounds.minY }.min()! - 10
        let maxX = validBlocks.map { $0.bounds.maxX }.max()! + 100 // Room for long lines
        let maxY = validBlocks.map { $0.bounds.maxY }.max()! + 10
        
        // Clamp to display bounds
        let clampedRect = CGRect(
            x: max(displayBounds.minX, minX),
            y: max(displayBounds.minY, minY),
            width: min(maxX - minX, displayBounds.width),
            height: min(maxY - minY, displayBounds.height)
        )
        
        // Must be a reasonably large region to be a real editor
        guard clampedRect.width > 80 && clampedRect.height > 60 else { return nil }
        
        return clampedRect
    }
    
    // MARK: - Language Detection
    
    private func detectLanguage(in text: String) -> String? {
        let lower = text.lowercased()
        
        // C++ specific
        if lower.contains("#include") || lower.contains("cout") ||
           lower.contains("cin") || lower.contains("vector<") ||
           lower.contains("std::") { return "C++" }
        
        // Python
        if lower.contains("def ") && lower.contains(":") &&
           !lower.contains("{") { return "Python" }
        
        // Java
        if lower.contains("public class") || lower.contains("system.out") ||
           lower.contains("arraylist") || lower.contains("hashmap") { return "Java" }
        
        // JavaScript / TypeScript
        if lower.contains("function") || lower.contains("const ") ||
           lower.contains("=>") || lower.contains("console.log") { return "JavaScript" }
        
        // Swift
        if lower.contains("func ") || lower.contains("guard ") ||
           lower.contains("@objc") || lower.contains("var ") && lower.contains("let ") { return "Swift" }
        
        // Go
        if lower.contains("func ") && lower.contains("package ") { return "Go" }
        
        // Rust
        if lower.contains("fn ") && lower.contains("mut ") { return "Rust" }
        
        // Fallback: if there are brackets + keywords, likely C-family
        if lower.contains("{") && lower.contains("}") { return "C/C++/Java" }
        
        return nil
    }
}
