// SemanticTreeBuilder.swift
// PshawBot
//
// The core fusion engine that merges window metadata, accessibility trees,
// vision layouts, and OCR text into a single cohesive SceneGraph.

import Foundation
import CoreGraphics
import OSLog

// MARK: - SemanticTreeBuilder

/// Fuses all detection sources into a unified `SceneGraph`.
actor SemanticTreeBuilder {
    
    private let logger = Logger(subsystem: "com.pshawbot", category: "SemanticTreeBuilder")
    
    // MARK: - API
    
    /// Builds a SceneGraph from the disparate detection inputs.
    ///
    /// - Parameters:
    ///   - frameID: The ID of the current frame.
    ///   - timestamp: The time of capture.
    ///   - windows: OS-level window metadata.
    ///   - axTrees: Accessibility trees (keyed by window ID).
    ///   - visionRegions: Layout regions detected by computer vision.
    ///   - ocrText: Text blocks extracted by OCR.
    /// - Returns: A unified `SceneGraph`.
    func buildGraph(
        frameID: UInt64,
        timestamp: Date,
        windows: [DetectedWindow],
        axTrees: [CGWindowID: AXNode],
        visionRegions: [DetectedRegion],
        ocrText: [RecognizedText]
    ) -> SceneGraph {
        
        var graph = SceneGraph(frameID: frameID, timestamp: timestamp)
        
        // 1. Add Windows (Roots)
        var windowNodes: [CGWindowID: SemanticNode] = [:]
        
        for window in windows {
            let node = SemanticNode(
                type: window.semanticType,
                source: .vision, // Technically OS API, but vision is close enough
                bounds: window.bounds,
                confidence: 1.0,
                recognizedText: window.title.isEmpty ? nil : window.title,
                windowID: window.id,
                metadata: ["appCategory": window.appCategory.rawValue],
                frameID: frameID
            )
            
            graph.addNode(node)
            windowNodes[window.id] = node
        }
        
        // 2. Add AX Trees
        for (windowID, axRoot) in axTrees {
            guard let windowNode = windowNodes[windowID] else { continue }
            
            _ = processAXNode(
                axRoot,
                parentID: windowNode.id,
                windowID: windowID,
                frameID: frameID,
                timestamp: timestamp,
                graph: &graph
            )
        }
        
        // 3. Overlay Vision Regions (Fallback where AX is missing)
        // For Phase 1, we simply add vision regions if they don't significantly overlap
        // with high-confidence AX regions.
        for region in visionRegions {
            // Find which window this region belongs to based on bounds
            guard let parentWindow = windows.first(where: { CoordinateConverter.isContained(region.bounds, within: $0.bounds, threshold: 0.8) }) else {
                continue
            }
            
            guard let parentNode = windowNodes[parentWindow.id] else { continue }
            
            // Check for overlap with existing AX nodes
            let existingNodes = graph.allNodes.filter { $0.windowID == parentWindow.id && $0.source == .accessibility }
            let hasOverlap = existingNodes.contains { axNode in
                CoordinateConverter.intersectionOverUnion(axNode.bounds, region.bounds) > 0.5
            }
            
            if !hasOverlap {
                let node = SemanticNode(
                    type: region.type,
                    source: .yolo,
                    bounds: region.bounds,
                    parentID: parentNode.id,
                    depth: parentNode.depth + 1,
                    confidence: region.confidence,
                    windowID: parentWindow.id,
                    frameID: frameID
                )
                
                graph.addNode(node)
                
                // Update parent
                var updatedParent = graph.node(id: parentNode.id)!
                updatedParent.childIDs.append(node.id)
                graph.updateNode(updatedParent)
            }
        }
        
        // 4. Attach OCR Text
        // Find the smallest enclosing region for each text block.
        for text in ocrText {
            // Find all nodes that contain this text block
            let containingNodes = graph.allNodes.filter { node in
                // Only attach text to interactive elements or generic containers
                (node.type.isInteractive || node.type == .panel || node.type == .textBlock) &&
                CoordinateConverter.isContained(text.bounds, within: node.bounds, threshold: 0.5)
            }
            
            // Pick the deepest (smallest) node
            if let targetNode = containingNodes.max(by: { $0.depth < $1.depth }) {
                var updatedNode = graph.node(id: targetNode.id)!
                
                // Append text if it already has some, otherwise set it
                if let existing = updatedNode.recognizedText {
                    updatedNode.recognizedText = existing + " " + text.string
                } else {
                    updatedNode.recognizedText = text.string
                }
                
                graph.updateNode(updatedNode)
            } else {
                // If no container, add as a standalone text block
                let node = SemanticNode(
                    type: .textBlock,
                    source: .ocr,
                    bounds: text.bounds,
                    confidence: text.confidence,
                    recognizedText: text.string,
                    windowID: text.windowID,
                    frameID: frameID
                )
                graph.addNode(node)
            }
        }
        
        return graph
    }
    
    // MARK: - Private Helpers
    
    /// Recursively processes an AXNode tree and adds it to the graph.
    private func processAXNode(
        _ axNode: AXNode,
        parentID: UUID,
        windowID: CGWindowID,
        frameID: UInt64,
        timestamp: Date,
        graph: inout SceneGraph
    ) -> UUID {
        
        let parentDepth = graph.node(id: parentID)?.depth ?? 0
        let currentDepth = parentDepth + 1
        
        let node = SemanticNode(
            type: axNode.semanticType,
            source: .accessibility,
            bounds: axNode.frame,
            parentID: parentID,
            depth: currentDepth,
            confidence: 1.0, // AX data is ground truth
            recognizedText: axNode.value ?? axNode.title,
            windowID: windowID,
            frameID: frameID
        )
        
        graph.addNode(node)
        
        // Update parent to include this child
        if var parent = graph.node(id: parentID) {
            parent.childIDs.append(node.id)
            graph.updateNode(parent)
        }
        
        // Process children
        for child in axNode.children {
            _ = processAXNode(
                child,
                parentID: node.id,
                windowID: windowID,
                frameID: frameID,
                timestamp: timestamp,
                graph: &graph
            )
        }
        
        return node.id
    }
}
