// TextBlockDetector.swift
// PshawBot
//
// Detects and clusters text blocks from OCR on screen.

import Foundation
import CoreGraphics
import Vision
import OSLog

struct DetectedTextBlock: Sendable, Identifiable {
    let id = UUID()
    let bounds: CGRect
    let text: String
    let isCode: Bool
    let language: String?
    
    var codeLines: [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

actor TextBlockDetector {
    
    private let logger = Logger(subsystem: "com.pshawbot", category: "TextBlockDetector")
    
    func detect(
        in image: CGImage,
        ocrBlocks: [RecognizedText],
        displayBounds: CGRect
    ) async -> [DetectedTextBlock] {
        
        guard !ocrBlocks.isEmpty else { return [] }
        
        // Basic proximity clustering — tight thresholds for smaller boxes.
        var clusters: [[RecognizedText]] = []
        
        for block in ocrBlocks {
            var addedToCluster = false
            for (idx, cluster) in clusters.enumerated() {
                let clusterRect = cluster.reduce(cluster[0].bounds) { $0.union($1.bounds) }
                // Moderate expansion: ~60pt horizontal (covers word gaps in emails), ~12pt vertical (one line gap)
                let expanded = clusterRect.insetBy(dx: -60, dy: -12)
                if expanded.intersects(block.bounds) {
                    clusters[idx].append(block)
                    addedToCluster = true
                    break
                }
            }
            if !addedToCluster {
                clusters.append([block])
            }
        }
        
        // Merge only truly overlapping clusters
        var merged = true
        while merged {
            merged = false
            for i in 0..<clusters.count {
                for j in (i+1)..<clusters.count {
                    let rect1 = clusters[i].reduce(clusters[i][0].bounds) { $0.union($1.bounds) }
                    let rect2 = clusters[j].reduce(clusters[j][0].bounds) { $0.union($1.bounds) }
                    
                    let expanded1 = rect1.insetBy(dx: -15, dy: -10)
                    if expanded1.intersects(rect2) {
                        clusters[i].append(contentsOf: clusters[j])
                        clusters.remove(at: j)
                        merged = true
                        break
                    }
                }
                if merged { break }
            }
        }
        
        // Split oversized clusters: if a cluster is taller than 350pt,
        // look for vertical gaps > 20pt and split there.
        var splitClusters: [[RecognizedText]] = []
        for cluster in clusters {
            let clusterRect = cluster.reduce(cluster[0].bounds) { $0.union($1.bounds) }
            if clusterRect.height > 350 {
                let sorted = cluster.sorted { $0.bounds.midY < $1.bounds.midY }
                var current: [RecognizedText] = [sorted[0]]
                for i in 1..<sorted.count {
                    let prevBottom = current.last!.bounds.maxY
                    let curTop = sorted[i].bounds.minY
                    if curTop - prevBottom > 20 {
                        splitClusters.append(current)
                        current = [sorted[i]]
                    } else {
                        current.append(sorted[i])
                    }
                }
                if !current.isEmpty { splitClusters.append(current) }
            } else {
                splitClusters.append(cluster)
            }
        }
        clusters = splitClusters
        
        var results: [DetectedTextBlock] = []
        
        for cluster in clusters {
            // Sort cluster for reading order
            let sortedCluster = cluster.sorted {
                if abs($0.bounds.midY - $1.bounds.midY) > 12 {
                    return $0.bounds.minY < $1.bounds.minY
                }
                return $0.bounds.minX < $1.bounds.minX
            }
            
            let clusterRect = sortedCluster.reduce(sortedCluster[0].bounds) { $0.union($1.bounds) }
            
            // Exclude noise
            guard clusterRect.width > 60 && clusterRect.height > 20 else { continue }
            
            var lines: [String] = []
            var currentLineBlocks: [RecognizedText] = []
            var currentLineY: CGFloat = -9999
            
            for block in sortedCluster {
                if abs(block.bounds.midY - currentLineY) > 12 {
                    if !currentLineBlocks.isEmpty {
                        lines.append(currentLineBlocks.map { $0.string }.joined(separator: " "))
                    }
                    currentLineBlocks = [block]
                    currentLineY = block.bounds.midY
                } else {
                    currentLineBlocks.append(block)
                }
            }
            if !currentLineBlocks.isEmpty {
                lines.append(currentLineBlocks.map { $0.string }.joined(separator: " "))
            }
            
            let rawText = lines.joined(separator: "\n")
            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let isCode = codeScore(for: rawText) > 0.15
            var finalCode: String = rawText
            var detectedLang: String? = nil
            
            if isCode {
                if let extracted = CodeLexer.extractCode(from: sortedCluster) {
                    finalCode = extracted
                }
                detectedLang = detectLanguage(in: finalCode)
            }
            
            results.append(DetectedTextBlock(
                bounds: clusterRect,
                text: finalCode,
                isCode: isCode,
                language: detectedLang
            ))
        }
        
        // Sort top-to-bottom, left-to-right
        results.sort {
            if abs($0.bounds.minY - $1.bounds.minY) > 100 {
                return $0.bounds.minY < $1.bounds.minY
            }
            return $0.bounds.minX < $1.bounds.minX
        }
        
        return results
    }
    
    private func codeScore(for text: String) -> Float {
        var score: Float = 0
        let words = text.split(separator: " ").map(String.init)
        
        let codeKeywords: Set<String> = [
            "int", "void", "return", "class", "public", "private", "protected",
            "static", "final", "const", "let", "var", "func", "fun", "def",
            "if", "else", "for", "while", "switch", "break", "continue"
        ]
        let codePatterns = ["{", "}", "()", ");", "//", "/*", "*/", "->", "::", "=="]
        
        let keywordHits = words.filter { codeKeywords.contains($0.lowercased()) }.count
        score += Float(keywordHits) * 0.15
        
        for pattern in codePatterns {
            if text.contains(pattern) { score += 0.1 }
        }
        
        let nonAlphaCount = text.filter { !$0.isLetter && !$0.isWhitespace }.count
        let ratio = Float(nonAlphaCount) / Float(max(text.count, 1))
        score += ratio * 0.3
        
        return min(1.0, score)
    }
    
    private func detectLanguage(in text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("#include") || lower.contains("std::") { return "C++" }
        if lower.contains("def ") && lower.contains(":") { return "Python" }
        if lower.contains("public class") { return "Java" }
        if lower.contains("function") || lower.contains("const ") { return "JavaScript" }
        if lower.contains("func ") { return "Swift" }
        if lower.contains("{") && lower.contains("}") { return "C/C++/Java" }
        return nil
    }
}
