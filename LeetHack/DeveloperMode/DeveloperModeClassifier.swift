// DeveloperModeClassifier.swift
// LeetHack
//
// Detects IDEs and classifies their internal structure heuristically.

import Foundation
import CoreGraphics
import OSLog

// MARK: - DeveloperModeClassifier

/// Enhances the semantic graph by identifying IDEs and classifying their specific
/// regions (editor, terminal, file explorer) using heuristic structural analysis.
actor DeveloperModeClassifier {
    
    private let logger = Logger(subsystem: "com.leethack", category: "DeveloperModeClassifier")
    
    // MARK: - API
    
    /// Enhances a scene graph with developer-specific classifications.
    ///
    /// - Parameter graph: The base scene graph.
    /// - Returns: A new scene graph with refined semantic types for IDE windows.
    func classify(_ graph: SceneGraph) -> SceneGraph {
        var enhancedGraph = graph
        
        // Find all windows classified as IDEs
        let ideWindows = graph.rootNodes.filter { 
            $0.metadata["appCategory"] == AppCategory.ide.rawValue 
        }
        
        for window in ideWindows {
            enhanceIDEWindow(windowID: window.id, in: &enhancedGraph)
        }
        
        return enhancedGraph
    }
    
    // MARK: - Private Helpers
    
    private func enhanceIDEWindow(windowID: UUID, in graph: inout SceneGraph) {
        // Get all nodes for this window
        let windowNodes = graph.allNodes.filter { $0.windowID == graph.node(id: windowID)?.windowID }
        
        // Find common IDE structures based on layout and text
        
        for node in windowNodes {
            var updatedNode = node
            var changed = false
            
            // 1. Identify Terminal / Console
            // Look for monospaced text with common shell prompts
            if let text = node.recognizedText, node.type == .panel || node.type == .textBlock {
                if text.contains("~ %") || text.contains("$ ") || text.contains("➜") || text.lowercased().contains("bash") || text.lowercased().contains("zsh") {
                    updatedNode.type = .terminal
                    changed = true
                }
            }
            
            // 2. Identify File Explorer
            // Look for tall, narrow panels on the left side
            if let windowNode = graph.node(id: windowID) {
                let isTallAndNarrow = node.bounds.height > node.bounds.width * 2
                let isOnLeftEdge = abs(node.bounds.minX - windowNode.bounds.minX) < 50
                
                if node.type == .panel && isTallAndNarrow && isOnLeftEdge {
                    updatedNode.type = .fileExplorer
                    changed = true
                }
            }
            
            // 3. Identify Code Editor
            // Look for the largest panel in the center
            if let windowNode = graph.node(id: windowID) {
                let isLarge = (node.bounds.width * node.bounds.height) > (windowNode.bounds.width * windowNode.bounds.height * 0.3)
                
                if (node.type == .panel || node.type == .mainContent) && isLarge && !changed {
                    updatedNode.type = .editor
                    changed = true
                    
                    // Attempt to extract language/file from title
                    if let title = windowNode.recognizedText {
                        if title.contains(".swift") {
                            updatedNode.metadata["language"] = "Swift"
                        } else if title.contains(".py") {
                            updatedNode.metadata["language"] = "Python"
                        } else if title.contains(".ts") {
                            updatedNode.metadata["language"] = "TypeScript"
                        }
                    }
                }
            }
            
            if changed {
                graph.updateNode(updatedNode)
            }
        }
    }
}
