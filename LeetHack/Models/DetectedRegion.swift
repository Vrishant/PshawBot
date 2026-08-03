// DetectedRegion.swift
// LeetHack
//
// Represents a structural region detected by computer vision models
// (either Apple Vision framework or YOLO).

import Foundation
import CoreGraphics

// MARK: - DetectedRegion

/// A visual region detected by the layout detection ML models.
struct DetectedRegion: Identifiable, Sendable {
    
    // MARK: - Identity
    
    /// Unique identifier for this region detection.
    let id: UUID
    
    // MARK: - Classification
    
    /// The semantic type of the region.
    let type: SemanticRegionType
    
    // MARK: - Geometry
    
    /// The bounding box of the region in screen coordinates (top-left origin).
    let bounds: CGRect
    
    // MARK: - Metadata
    
    /// The model's confidence in the detection (0.0 to 1.0).
    let confidence: Float
    
    /// The source window this region belongs to, if known.
    let windowID: CGWindowID?
    
    /// The name of the detector that produced this result (e.g. "VisionLayoutDetector").
    let sourceDetector: String
    
    // MARK: - Initialisation
    
    init(
        id: UUID = UUID(),
        type: SemanticRegionType,
        bounds: CGRect,
        confidence: Float,
        windowID: CGWindowID? = nil,
        sourceDetector: String
    ) {
        self.id = id
        self.type = type
        self.bounds = bounds
        self.confidence = confidence
        self.windowID = windowID
        self.sourceDetector = sourceDetector
    }
}
