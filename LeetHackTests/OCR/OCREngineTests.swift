// OCREngineTests.swift
// LeetHackTests

import XCTest
@testable import LeetHack
import CoreGraphics

final class OCREngineTests: XCTestCase {
    
    func testOCREngineInitialization() async {
        let engine = OCREngine(recognitionLevel: .accurate)
        XCTAssertNotNil(engine)
    }
    
    // In a real environment, we'd load a test image and verify text extraction.
    // For now, this just tests the RecognizedText model.
    func testRecognizedTextModel() {
        let bounds = CGRect(x: 10, y: 10, width: 100, height: 20)
        let text = RecognizedText(string: "Test String", bounds: bounds, confidence: 0.95)
        
        XCTAssertEqual(text.string, "Test String")
        XCTAssertEqual(text.bounds, bounds)
        XCTAssertEqual(text.confidence, 0.95)
        XCTAssertNotNil(text.id)
    }
}
