// IconDetector.swift
// LeetHack
//
// Heuristic detector for small square regions that are likely icons.

import Foundation
import CoreGraphics

// MARK: - IconDetector

/// A heuristic-based detector that identifies icon buttons based on geometry.
actor IconDetector {
    
    func filterIcons(from regions: [DetectedRegion]) -> [DetectedRegion] {
        return regions.map { region in
            let bounds = region.bounds
            
            // Icons are typically small and perfectly square
            let isSmall = bounds.width >= 12 && bounds.width <= 48
            let isSquare = abs(bounds.width - bounds.height) < 4
            
            if isSmall && isSquare && region.type == .panel {
                // Refine generic panel into an icon button
                return DetectedRegion(
                    id: region.id,
                    type: .iconButton,
                    bounds: bounds,
                    confidence: region.confidence,
                    windowID: region.windowID,
                    sourceDetector: "IconDetector (Heuristic)"
                )
            }
            
            return region
        }
    }
}
