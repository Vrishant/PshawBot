// SceneGraph.swift
// LeetHack
//
// Represents the full semantic understanding of the screen for a single frame.

import Foundation
import CoreGraphics

// MARK: - SceneGraph

/// The complete hierarchical semantic representation of a captured frame.
///
/// Nodes are stored in a flat dictionary for O(1) lookups, with parent/child
/// relationships maintained via UUID references.
struct SceneGraph: Sendable, Equatable {
    
    // MARK: - State
    
    /// The ID of the frame this graph represents.
    let frameID: UInt64
    
    /// The timestamp of the frame.
    let timestamp: Date
    
    /// Flat storage of all nodes in the graph, keyed by their UUID.
    private(set) var nodes: [UUID: SemanticNode]
    
    /// The UUIDs of the root nodes (typically windows and the menu bar).
    private(set) var rootIDs: [UUID]
    
    // MARK: - Initialisation
    
    init(frameID: UInt64, timestamp: Date, nodes: [UUID: SemanticNode] = [:], rootIDs: [UUID] = []) {
        self.frameID = frameID
        self.timestamp = timestamp
        self.nodes = nodes
        self.rootIDs = rootIDs
    }
    
    // MARK: - Query API
    
    /// Returns the node with the specified ID.
    func node(id: UUID) -> SemanticNode? {
        return nodes[id]
    }
    
    /// Returns all child nodes of the specified parent.
    func children(of parentID: UUID) -> [SemanticNode] {
        guard let parent = nodes[parentID] else { return [] }
        return parent.childIDs.compactMap { nodes[$0] }
    }
    
    /// Returns the parent node of the specified child.
    func parent(of childID: UUID) -> SemanticNode? {
        guard let child = nodes[childID], let parentID = child.parentID else { return nil }
        return nodes[parentID]
    }
    
    /// Returns all root nodes.
    var rootNodes: [SemanticNode] {
        return rootIDs.compactMap { nodes[$0] }
    }
    
    /// Returns all nodes in the graph.
    var allNodes: [SemanticNode] {
        return Array(nodes.values)
    }
    
    /// Returns all nodes of a specific type.
    func nodes(ofType type: SemanticRegionType) -> [SemanticNode] {
        return nodes.values.filter { $0.type == type }
    }
    
    /// Finds all nodes whose recognized text contains the search string.
    func search(text: String, caseSensitive: Bool = false) -> [SemanticNode] {
        let query = caseSensitive ? text : text.lowercased()
        
        return nodes.values.filter { node in
            guard let nodeText = node.recognizedText else { return false }
            return caseSensitive ? nodeText.contains(query) : nodeText.lowercased().contains(query)
        }
    }
    
    // MARK: - Modification (Internal/Builder use)
    
    mutating func addNode(_ node: SemanticNode) {
        nodes[node.id] = node
        
        if node.parentID == nil && !rootIDs.contains(node.id) {
            rootIDs.append(node.id)
        }
    }
    
    mutating func updateNode(_ node: SemanticNode) {
        nodes[node.id] = node
    }
    
    mutating func removeNode(_ id: UUID) {
        guard let node = nodes[id] else { return }
        
        // Remove from parent's children list
        if let parentID = node.parentID, var parent = nodes[parentID] {
            parent.childIDs.removeAll { $0 == id }
            nodes[parentID] = parent
        }
        
        // Remove from roots
        rootIDs.removeAll { $0 == id }
        
        // Remove the node itself
        nodes.removeValue(forKey: id)
        
        // Cascading delete is not implemented here for safety;
        // tree builders should construct valid trees.
    }
}
