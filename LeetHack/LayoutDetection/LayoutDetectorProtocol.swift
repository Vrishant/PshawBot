// LayoutDetectorProtocol.swift
// LeetHack
//
// Defines the interface for layout detection modules. This allows us to
// hot-swap the Apple Vision implementation with a YOLO implementation later.

import Foundation
import CoreGraphics

// MARK: - LayoutDetectorProtocol

/// A protocol for computer vision models that detect structural regions
/// in an image.
///
/// By conforming to this protocol, we can swap between different ML models
/// (e.g. Apple Vision `VNDetectRectanglesRequest`, CoreML YOLO, DocLayout-YOLO)
/// without changing the pipeline orchestration.
protocol LayoutDetectorProtocol: Sendable {
    
    /// The human-readable name of the detector (e.g. "Apple Vision", "YOLOv11").
    var name: String { get }
    
    /// The set of region types this detector is capable of identifying.
    var supportedRegionTypes: Set<SemanticRegionType> { get }
    
    /// Detects regions in the provided image.
    ///
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - bounds: The screen-space bounds of the image (used for coordinate conversion).
    /// - Returns: An array of detected regions.
    /// - Throws: An error if detection fails.
    func detectRegions(in image: CGImage, within bounds: CGRect) async throws -> [DetectedRegion]
}

// MARK: - DetectionSource

/// Identifies the subsystem that generated a semantic node.
enum DetectionSource: String, Sendable, Codable {
    case accessibility = "Accessibility API"
    case vision = "Vision Framework"
    case ocr = "OCR Engine"
    case yolo = "YOLO Model"
    case heuristic = "Heuristic Classifier"
    case fused = "Fused Node"
}
