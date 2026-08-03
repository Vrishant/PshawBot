// AccessibilityScannerTests.swift
// LeetHackTests

import XCTest
@testable import LeetHack

final class AccessibilityScannerTests: XCTestCase {
    
    func testScannerInitialization() async {
        let scanner = AccessibilityScanner()
        XCTAssertNotNil(scanner)
        
        // We can't easily test actual AX traversal in a unit test without mocking
        // the AXUIElement API (which is a C API), but we can verify the AXNode flattening.
        
        let child = AXNode(role: "AXButton", subrole: nil, semanticType: .button, title: "Click Me", value: nil, frame: .zero, children: [], depth: 1)
        let root = AXNode(role: "AXWindow", subrole: nil, semanticType: .window, title: "Test Window", value: nil, frame: .zero, children: [child], depth: 0)
        
        let flattened = root.flatten()
        XCTAssertEqual(flattened.count, 2)
        XCTAssertEqual(flattened[0].role, "AXWindow")
        XCTAssertEqual(flattened[1].role, "AXButton")
    }
}
