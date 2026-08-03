// UIElementDetector.swift
// LeetHack
//
// Heuristic-based detector that identifies UI elements by combining layout
// boundaries and OCR text.

import Foundation
import CoreGraphics

// MARK: - UIElementDetector

/// A heuristic-based detector that infers interactive UI elements by combining
/// the outputs of the layout detector (rectangles) and OCR engine (text).
///
/// For example, if a small rectangle contains short text like "Submit" or "Cancel",
/// it is highly likely to be a button.
actor UIElementDetector {
    
    func inferElements(from regions: [DetectedRegion], textBlocks: [RecognizedText]) -> [DetectedRegion] {
        var inferredElements: [DetectedRegion] = []
        
        for region in regions {
            // Find all text blocks that are entirely contained within this region
            let containedText = textBlocks.filter { text in
                CoordinateConverter.isContained(text.bounds, within: region.bounds)
            }
            
            // If the region contains exactly one short piece of text, it's likely a button
            // or an input field.
            if containedText.count == 1, let text = containedText.first {
                let string = text.string
                
                let isLikelyButton = isButtonText(string)
                let isLikelyInput = region.bounds.width > region.bounds.height * 3 && !isLikelyButton
                
                if isLikelyButton {
                    let refined = DetectedRegion(
                        id: region.id,
                        type: .button,
                        bounds: region.bounds,
                        confidence: region.confidence * text.confidence,
                        windowID: region.windowID,
                        sourceDetector: "UIElementDetector (Heuristic)"
                    )
                    inferredElements.append(refined)
                } else if isLikelyInput {
                    let refined = DetectedRegion(
                        id: region.id,
                        type: .textInput,
                        bounds: region.bounds,
                        confidence: region.confidence * text.confidence,
                        windowID: region.windowID,
                        sourceDetector: "UIElementDetector (Heuristic)"
                    )
                    inferredElements.append(refined)
                } else {
                    inferredElements.append(region)
                }
            } else {
                inferredElements.append(region)
            }
        }
        
        return inferredElements
    }
    
    private func isButtonText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let commonVerbs = ["ok", "cancel", "submit", "save", "apply", "close", "open", "done", "next", "back", "login", "sign in"]
        return commonVerbs.contains(lower) || (text.count < 15 && !text.contains("\n"))
    }
}
