// ChangeTracker.swift
// PshawBot
//
// Calculates the diff between two SceneGraphs to drive animations and reduce
// redundant processing.

import Foundation

// MARK: - ChangeTracker

/// Compares consecutive `SceneGraph` instances to find added, removed, and
/// modified nodes.
actor ChangeTracker {
    
    func computeDiff(from oldGraph: SceneGraph?, to newGraph: SceneGraph) -> SceneGraphDiff {
        guard let old = oldGraph else {
            // First frame: everything is added
            return SceneGraphDiff(
                added: Set(newGraph.allNodes.map { $0.id }),
                removed: [],
                modified: []
            )
        }
        
        var added: Set<UUID> = []
        var removed: Set<UUID> = []
        var modified: Set<UUID> = []
        
        let oldNodes = old.allNodes
        let newNodes = newGraph.allNodes
        
        // In a real system, we'd use stable IDs (like AX identifiers or geometric hashes)
        // to track nodes across frames. For Phase 1, we simulate this by trying to match
        // nodes based on exact bounds and type.
        
        var unmatchedOld = Set(oldNodes.map { $0.id })
        
        for newNode in newNodes {
            // Find a match in the old graph
            let match = oldNodes.first { oldNode in
                unmatchedOld.contains(oldNode.id) &&
                oldNode.type == newNode.type &&
                CoordinateConverter.intersectionOverUnion(oldNode.bounds, newNode.bounds) > 0.8
            }
            
            if let matchedNode = match {
                unmatchedOld.remove(matchedNode.id)
                // Check if it was modified (e.g. text changed)
                if matchedNode.recognizedText != newNode.recognizedText ||
                   matchedNode.bounds != newNode.bounds {
                    modified.insert(newNode.id)
                }
            } else {
                added.insert(newNode.id)
            }
        }
        
        // Anything left in unmatchedOld was removed
        removed = unmatchedOld
        
        return SceneGraphDiff(added: added, removed: removed, modified: modified)
    }
}

// MARK: - SceneGraphDiff

/// Represents the changes between two frames.
struct SceneGraphDiff: Sendable {
    let added: Set<UUID>
    let removed: Set<UUID>
    let modified: Set<UUID>
    
    var hasChanges: Bool {
        !added.isEmpty || !removed.isEmpty || !modified.isEmpty
    }
}
