// RecognizedText.swift
// PshawBot
//
// Represents text extracted from the screen via OCR.

import Foundation
import CoreGraphics

// MARK: - RecognizedText

/// A piece of text recognized on the screen by the OCR engine.
struct RecognizedText: Identifiable, Sendable {
    
    // MARK: - Identity
    
    /// Unique identifier for this text block.
    let id: UUID
    
    // MARK: - Content
    
    /// The actual recognized text string.
    let string: String
    
    // MARK: - Geometry
    
    /// The bounding box of the text in screen coordinates (top-left origin).
    let bounds: CGRect
    
    // MARK: - Metadata
    
    /// The engine's confidence in the recognition (0.0 to 1.0).
    let confidence: Float
    
    /// The source window this text was found in, if known.
    let windowID: CGWindowID?
    
    // MARK: - Initialisation
    
    init(
        id: UUID = UUID(),
        string: String,
        bounds: CGRect,
        confidence: Float,
        windowID: CGWindowID? = nil
    ) {
        self.id = id
        self.string = string
        self.bounds = bounds
        self.confidence = confidence
        self.windowID = windowID
    }
}
