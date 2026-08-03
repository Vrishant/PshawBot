// CoordinateConverterTests.swift
// LeetHackTests
//
// Unit tests for the CoordinateConverter utility.

import XCTest
@testable import LeetHack

final class CoordinateConverterTests: XCTestCase {
    
    // MARK: - Top-Left ↔ Bottom-Left Conversion
    
    func testTopLeftToBottomLeft() {
        let rect = CGRect(x: 100, y: 50, width: 200, height: 100)
        let displayHeight: CGFloat = 1080
        
        let converted = CoordinateConverter.topLeftToBottomLeft(rect, displayHeight: displayHeight)
        
        XCTAssertEqual(converted.origin.x, 100)
        XCTAssertEqual(converted.origin.y, 930) // 1080 - 50 - 100
        XCTAssertEqual(converted.width, 200)
        XCTAssertEqual(converted.height, 100)
    }
    
    func testBottomLeftToTopLeft() {
        let rect = CGRect(x: 100, y: 930, width: 200, height: 100)
        let displayHeight: CGFloat = 1080
        
        let converted = CoordinateConverter.bottomLeftToTopLeft(rect, displayHeight: displayHeight)
        
        XCTAssertEqual(converted.origin.x, 100)
        XCTAssertEqual(converted.origin.y, 50) // 1080 - 930 - 100
        XCTAssertEqual(converted.width, 200)
        XCTAssertEqual(converted.height, 100)
    }
    
    func testRoundTripTopLeftBottomLeft() {
        let original = CGRect(x: 300, y: 200, width: 400, height: 300)
        let displayHeight: CGFloat = 1440
        
        let converted = CoordinateConverter.topLeftToBottomLeft(original, displayHeight: displayHeight)
        let roundTrip = CoordinateConverter.bottomLeftToTopLeft(converted, displayHeight: displayHeight)
        
        XCTAssertEqual(roundTrip.origin.x, original.origin.x, accuracy: 0.001)
        XCTAssertEqual(roundTrip.origin.y, original.origin.y, accuracy: 0.001)
        XCTAssertEqual(roundTrip.width, original.width, accuracy: 0.001)
        XCTAssertEqual(roundTrip.height, original.height, accuracy: 0.001)
    }
    
    // MARK: - Vision ↔ Screen Conversion
    
    func testVisionToScreen() {
        // A normalised rect in the bottom-left of the image
        let normalised = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3)
        let imageSize = CGSize(width: 1920, height: 1080)
        
        let screen = CoordinateConverter.visionToScreen(normalizedRect: normalised, imageSize: imageSize)
        
        // x = 0.1 * 1920 = 192
        XCTAssertEqual(screen.origin.x, 192, accuracy: 0.001)
        // y = (1 - 0.2 - 0.3) * 1080 = 0.5 * 1080 = 540
        XCTAssertEqual(screen.origin.y, 540, accuracy: 0.001)
        // width = 0.5 * 1920 = 960
        XCTAssertEqual(screen.width, 960, accuracy: 0.001)
        // height = 0.3 * 1080 = 324
        XCTAssertEqual(screen.height, 324, accuracy: 0.001)
    }
    
    func testScreenToVision() {
        let pixelRect = CGRect(x: 192, y: 540, width: 960, height: 324)
        let imageSize = CGSize(width: 1920, height: 1080)
        
        let normalised = CoordinateConverter.screenToVision(pixelRect: pixelRect, imageSize: imageSize)
        
        XCTAssertEqual(normalised.origin.x, 0.1, accuracy: 0.001)
        XCTAssertEqual(normalised.origin.y, 0.2, accuracy: 0.001)
        XCTAssertEqual(normalised.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(normalised.height, 0.3, accuracy: 0.001)
    }
    
    func testRoundTripVisionScreen() {
        let original = CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.6)
        let imageSize = CGSize(width: 2560, height: 1600)
        
        let screen = CoordinateConverter.visionToScreen(normalizedRect: original, imageSize: imageSize)
        let roundTrip = CoordinateConverter.screenToVision(pixelRect: screen, imageSize: imageSize)
        
        XCTAssertEqual(roundTrip.origin.x, original.origin.x, accuracy: 0.001)
        XCTAssertEqual(roundTrip.origin.y, original.origin.y, accuracy: 0.001)
        XCTAssertEqual(roundTrip.width, original.width, accuracy: 0.001)
        XCTAssertEqual(roundTrip.height, original.height, accuracy: 0.001)
    }
    
    // MARK: - Window-Relative Conversion
    
    func testScreenToWindow() {
        let screenRect = CGRect(x: 150, y: 250, width: 100, height: 50)
        let windowBounds = CGRect(x: 100, y: 200, width: 800, height: 600)
        
        let windowRelative = CoordinateConverter.screenToWindow(screenRect: screenRect, windowBounds: windowBounds)
        
        XCTAssertNotNil(windowRelative)
        XCTAssertEqual(windowRelative!.origin.x, 50) // 150 - 100
        XCTAssertEqual(windowRelative!.origin.y, 50) // 250 - 200
        XCTAssertEqual(windowRelative!.width, 100)
        XCTAssertEqual(windowRelative!.height, 50)
    }
    
    func testScreenToWindowNoIntersection() {
        let screenRect = CGRect(x: 1000, y: 1000, width: 100, height: 50)
        let windowBounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        
        let result = CoordinateConverter.screenToWindow(screenRect: screenRect, windowBounds: windowBounds)
        XCTAssertNil(result)
    }
    
    func testWindowToScreen() {
        let windowRect = CGRect(x: 50, y: 50, width: 100, height: 50)
        let windowBounds = CGRect(x: 100, y: 200, width: 800, height: 600)
        
        let screen = CoordinateConverter.windowToScreen(windowRect: windowRect, windowBounds: windowBounds)
        
        XCTAssertEqual(screen.origin.x, 150) // 50 + 100
        XCTAssertEqual(screen.origin.y, 250) // 50 + 200
    }
    
    // MARK: - IoU Tests
    
    func testIoUIdenticalRects() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let iou = CoordinateConverter.intersectionOverUnion(rect, rect)
        XCTAssertEqual(iou, 1.0, accuracy: 0.001)
    }
    
    func testIoUNoOverlap() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 200, y: 200, width: 100, height: 100)
        let iou = CoordinateConverter.intersectionOverUnion(a, b)
        XCTAssertEqual(iou, 0.0, accuracy: 0.001)
    }
    
    func testIoUPartialOverlap() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 50, y: 50, width: 100, height: 100)
        let iou = CoordinateConverter.intersectionOverUnion(a, b)
        
        // Intersection: 50×50 = 2500
        // Union: 10000 + 10000 - 2500 = 17500
        // IoU: 2500 / 17500 ≈ 0.1429
        XCTAssertEqual(iou, 2500.0 / 17500.0, accuracy: 0.001)
    }
    
    // MARK: - Containment Tests
    
    func testIsContainedFully() {
        let inner = CGRect(x: 10, y: 10, width: 50, height: 50)
        let outer = CGRect(x: 0, y: 0, width: 100, height: 100)
        
        XCTAssertTrue(CoordinateConverter.isContained(inner, within: outer))
    }
    
    func testIsContainedPartially() {
        let inner = CGRect(x: 80, y: 80, width: 50, height: 50)
        let outer = CGRect(x: 0, y: 0, width: 100, height: 100)
        
        // Only 20×20 = 400 out of 2500 is contained (16%)
        XCTAssertFalse(CoordinateConverter.isContained(inner, within: outer))
    }
    
    func testIsContainedWithCustomThreshold() {
        let inner = CGRect(x: 80, y: 80, width: 50, height: 50)
        let outer = CGRect(x: 0, y: 0, width: 100, height: 100)
        
        // With a very low threshold, it should pass
        XCTAssertTrue(CoordinateConverter.isContained(inner, within: outer, threshold: 0.1))
    }
}
