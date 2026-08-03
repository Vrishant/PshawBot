// SemanticNode.swift
// LeetHack
//
// The core unit of the semantic tree representing a distinct region of the screen.

import Foundation
import CoreGraphics

// MARK: - SemanticNode

/// A unified representation of a UI element or semantic region on the screen.
///
/// This is the end result of fusing all our detection sources (Window, AX,
/// Vision, OCR). It contains the geometry, type classification, and any extracted
/// text or embeddings.
struct SemanticNode: Identifiable, Equatable, Sendable {
    
    // MARK: - Identity
    
    /// Unique identifier for this node (regenerated per frame).
    let id: UUID
    
    /// A stable identifier across frames, if possible (e.g. from AX tree).
    let stableID: String?
    
    // MARK: - Classification
    
    /// The semantic type of this region.
    var type: SemanticRegionType
    
    /// The source that generated this node (e.g., .accessibility, .vision, .fused).
    var source: DetectionSource
    
    // MARK: - Geometry
    
    /// The bounding box in screen coordinates (top-left origin).
    var bounds: CGRect
    
    // MARK: - Hierarchy
    
    /// The ID of the parent node, if any.
    var parentID: UUID?
    
    /// The IDs of all child nodes.
    var childIDs: [UUID]
    
    /// The depth of this node in the hierarchy (0 = root).
    var depth: Int
    
    // MARK: - Content & Metadata
    
    /// Confidence score (0.0 to 1.0).
    var confidence: Float
    
    /// Text extracted via OCR or AX value.
    var recognizedText: String?
    
    /// The window ID this node belongs to, if any.
    var windowID: CGWindowID?
    
    /// Optional vision embedding vector (e.g., CLIP) for semantic search.
    var visualEmbedding: [Float]?
    
    /// Additional metadata specific to the region type (e.g., code language, git branch).
    var metadata: [String: String]
    
    // MARK: - Temporal
    
    /// The timestamp when this node was created/detected.
    let timestamp: Date
    
    /// The frame ID this node belongs to.
    let frameID: UInt64
    
    /// Whether this node was NOT seen in the latest frame (used for fade-out animations).
    var isStale: Bool = false
    
    // MARK: - Initialisation
    
    init(
        id: UUID = UUID(),
        stableID: String? = nil,
        type: SemanticRegionType,
        source: DetectionSource,
        bounds: CGRect,
        parentID: UUID? = nil,
        childIDs: [UUID] = [],
        depth: Int = 0,
        confidence: Float = 1.0,
        recognizedText: String? = nil,
        windowID: CGWindowID? = nil,
        visualEmbedding: [Float]? = nil,
        metadata: [String: String] = [:],
        timestamp: Date = Date(),
        frameID: UInt64
    ) {
        self.id = id
        self.stableID = stableID
        self.type = type
        self.source = source
        self.bounds = bounds
        self.parentID = parentID
        self.childIDs = childIDs
        self.depth = depth
        self.confidence = confidence
        self.recognizedText = recognizedText
        self.windowID = windowID
        self.visualEmbedding = visualEmbedding
        self.metadata = metadata
        self.timestamp = timestamp
        self.frameID = frameID
    }
}
