// WindowDetectorTests.swift
// PshawBotTests

import XCTest
@testable import PshawBot

final class WindowDetectorTests: XCTestCase {
    
    func testDetectWindowsReturnsResults() async {
        let detector = WindowDetector()
        
        // This relies on the system having at least one visible window (which it should)
        let windows = await detector.detectWindows()
        
        XCTAssertFalse(windows.isEmpty, "Should detect at least one window")
        
        // Find a known window if possible, like Finder or the current app
        if let window = windows.first {
            XCTAssertNotNil(window.id)
            XCTAssertGreaterThan(window.ownerPID, 0)
            XCTAssertFalse(window.ownerName.isEmpty)
        }
    }
    
    func testAppCategoryClassification() {
        let ideWindow = DetectedWindow(id: 1, ownerPID: 1, ownerName: "Visual Studio Code", title: "", bounds: .zero, layer: 0, alpha: 1, isOnScreen: true)
        XCTAssertEqual(ideWindow.appCategory, .ide)
        
        let browserWindow = DetectedWindow(id: 2, ownerPID: 2, ownerName: "Google Chrome", title: "", bounds: .zero, layer: 0, alpha: 1, isOnScreen: true)
        XCTAssertEqual(browserWindow.appCategory, .browser)
        
        let terminalWindow = DetectedWindow(id: 3, ownerPID: 3, ownerName: "Warp", title: "", bounds: .zero, layer: 0, alpha: 1, isOnScreen: true)
        XCTAssertEqual(terminalWindow.appCategory, .terminal)
    }
}
