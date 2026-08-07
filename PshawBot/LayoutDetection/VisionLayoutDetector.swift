// VisionLayoutDetector.swift
// PshawBot
//
// Apple Vision framework implementation of the layout detector.
// Uses VNDetectRectanglesRequest to find generic structural boundaries.

import Foundation
import Vision
import CoreGraphics
import OSLog

// MARK: - VisionLayoutDetector

/// A layout detector using Apple's built-in Vision framework.
///
/// This detector uses `VNDetectRectanglesRequest` to find UI structures.
/// While it cannot specifically classify *what* a rectangle is (e.g. it can't
/// distinguish a sidebar from a terminal pane on its own), it is excellent
/// at finding the boundaries of these containers very quickly.
actor VisionLayoutDetector: LayoutDetectorProtocol {
    
    let name = "Apple Vision Framework"
    
    // We only detect generic panels/containers with this approach.
    let supportedRegionTypes: Set<SemanticRegionType> = [.panel, .image, .textBlock]
    
    private let logger = Logger(subsystem: "com.pshawbot", category: "VisionLayoutDetector")
    
    func detectRegions(in image: CGImage, within bounds: CGRect) async throws -> [DetectedRegion] {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.5
        request.maximumObservations = 50
        request.minimumSize = 0.02
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        
        guard let results = request.results, !results.isEmpty else {
            return []
        }
        
        let imageSize = CGSize(width: image.width, height: image.height)
        var regions: [DetectedRegion] = []
        
        for observation in results {
            let screenBounds = CoordinateConverter.visionToScreen(
                normalizedRect: observation.boundingBox,
                imageSize: imageSize
            )
            
            let finalBounds = CGRect(
                x: screenBounds.origin.x + bounds.origin.x,
                y: screenBounds.origin.y + bounds.origin.y,
                width: screenBounds.width,
                height: screenBounds.height
            )
            
            let area = finalBounds.width * finalBounds.height
            let boundsArea = bounds.width * bounds.height
            
            guard area > 100, area < (boundsArea * 0.95) else {
                continue
            }
            
            let region = DetectedRegion(
                type: .panel,
                bounds: finalBounds,
                confidence: observation.confidence,
                sourceDetector: self.name
            )
            regions.append(region)
        }
        
        return regions
    }
}
