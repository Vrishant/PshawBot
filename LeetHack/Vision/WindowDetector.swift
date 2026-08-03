// WindowDetector.swift
// LeetHack
//
// Wraps CoreGraphics window list APIs to detect all visible windows on screen.
// This forms the top level of our semantic graph (root nodes).

import Foundation
import CoreGraphics
import OSLog

// MARK: - WindowDetector

/// Detects and tracks all visible windows on the macOS desktop.
///
/// Uses `CGWindowListCopyWindowInfo` to get the ground truth of window layout.
/// This is extremely fast and reliable, providing perfect bounding boxes for
/// applications, regardless of whether they support accessibility or not.
actor WindowDetector {
    
    // MARK: - State
    
    /// The previously detected windows. Used for diffing.
    private var previousWindows: [CGWindowID: DetectedWindow] = [:]
    
    /// Logger for this module.
    private let logger = Logger(subsystem: "com.leethack", category: "WindowDetector")
    
    // MARK: - API
    
    /// Detects all currently visible windows on the screen.
    ///
    /// - Returns: An array of `DetectedWindow` objects, ordered from front to back.
    func detectWindows() -> [DetectedWindow] {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        
        // This is a C API that returns an untyped CFArray of CFDictionaries
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            logger.error("Failed to copy window info from CoreGraphics")
            return []
        }
        
        var detectedWindows: [DetectedWindow] = []
        let displayBounds = CoordinateConverter.primaryDisplayBounds
        
        for windowInfo in windowList {
            // Extract required properties
            guard
                let id = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                let layer = windowInfo[kCGWindowLayer as String] as? Int,
                let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                let x = boundsDict["X"],
                let y = boundsDict["Y"],
                let width = boundsDict["Width"],
                let height = boundsDict["Height"]
            else {
                continue
            }
            
            // Extract optional properties
            let title = windowInfo[kCGWindowName as String] as? String ?? ""
            let alpha = windowInfo[kCGWindowAlpha as String] as? Float ?? 1.0
            let isOnScreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool ?? true
            
            // Ignore transparent or tiny utility windows
            guard alpha > 0.1, width > 50, height > 50 else { continue }
            
            // Ignore desktop wallpapers and background icons (layer < 0)
            // Also ignore system overlays (layer > 0, like Spotlight, Notification Center)
            // Normal app windows live at layer 0.
            guard layer == 0 else { continue }
            
            // Ignore system UI elements like Menubar, Dock, Control Center, etc.
            let systemProcesses: Set<String> = [
                "WindowServer", "Dock", "Control Center", "NotificationCenter",
                "SystemUIServer", "Spotlight", "AXVisualSupportAgent",
                "universalAccessAuthWarn", "TextInputMenuAgent",
                "Wi-Fi", "Bluetooth"
            ]
            guard !systemProcesses.contains(ownerName) else { continue }
            
            // Ignore our own app's windows so they don't pollute the semantic graph
            guard ownerPID != ProcessInfo.processInfo.processIdentifier else { continue }
            
            // Ignore semi-transparent overlays (likely ghost panels)
            guard alpha > 0.8 else { continue }
            
            let bounds = CGRect(x: x, y: y, width: width, height: height)
            
            // Ignore windows entirely outside the primary display
            // (In a multi-monitor setup, we'd need to handle this differently,
            // but for Phase 1 we focus on the main display).
            guard bounds.intersects(displayBounds) else {
                continue
            }
            
            let window = DetectedWindow(
                id: id,
                ownerPID: ownerPID,
                ownerName: ownerName,
                title: title,
                bounds: bounds,
                layer: layer,
                alpha: alpha,
                isOnScreen: isOnScreen
            )
            
            detectedWindows.append(window)
        }
        
        // Update cache
        var newCache: [CGWindowID: DetectedWindow] = [:]
        for window in detectedWindows {
            newCache[window.id] = window
        }
        previousWindows = newCache
        
        return detectedWindows
    }
    
    /// Filters a list of windows to return only those that belong to a specific category.
    func filter(_ windows: [DetectedWindow], for category: AppCategory) -> [DetectedWindow] {
        return windows.filter { $0.appCategory == category }
    }
}
