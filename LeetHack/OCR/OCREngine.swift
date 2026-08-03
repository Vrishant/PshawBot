// OCREngine.swift
// LeetHack
//
// Extracts text from screen crops using Apple Vision's VNRecognizeTextRequest.

import Foundation
import Vision
import CoreGraphics
import OSLog

// MARK: - OCREngine

/// The Optical Character Recognition engine powered by Apple Vision.
actor OCREngine {
    
    // MARK: - Configuration
    
    /// The recognition level to use. `.accurate` is slower but better;
    /// `.fast` is real-time but misses small text. We default to `.accurate`
    /// because we only run OCR on specific window crops, not the whole screen.
    let recognitionLevel: VNRequestTextRecognitionLevel
    
    private let logger = Logger(subsystem: "com.leethack", category: "OCREngine")
    
    init(recognitionLevel: VNRequestTextRecognitionLevel = .accurate) {
        self.recognitionLevel = recognitionLevel
    }
    
    // MARK: - API
    
    /// Extracts text from the provided image.
    ///
    /// - Parameters:
    ///   - image: The image to analyse (typically a crop of a single window).
    ///   - bounds: The screen-space bounds of the image (used for coordinate conversion).
    /// - Returns: An array of recognized text blocks.
    func recognizeText(in image: CGImage, within bounds: CGRect) async throws -> [RecognizedText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = self.recognitionLevel
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        
        guard let results = request.results, !results.isEmpty else {
            return []
        }
        
        let imageSize = CGSize(width: image.width, height: image.height)
        var recognizedBlocks: [RecognizedText] = []
        
        for observation in results {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            let string = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !string.isEmpty else { continue }
            
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
            
            let text = RecognizedText(
                string: string,
                bounds: finalBounds,
                confidence: topCandidate.confidence
            )
            
            recognizedBlocks.append(text)
        }
        
        return recognizedBlocks
    }
}
