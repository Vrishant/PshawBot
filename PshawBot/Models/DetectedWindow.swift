// DetectedWindow.swift
// PshawBot
//
// Represents a macOS window detected by CGWindowListCopyWindowInfo.

import Foundation
import CoreGraphics

// MARK: - DetectedWindow

/// Represents metadata about a macOS window obtained from CoreGraphics.
struct DetectedWindow: Identifiable, Sendable {
    
    // MARK: - Identity
    
    /// The unique CoreGraphics window identifier.
    let id: CGWindowID
    
    /// The process ID (PID) of the application that owns the window.
    let ownerPID: Int32
    
    /// The localised name of the application that owns the window.
    let ownerName: String
    
    /// The title of the window, if available.
    let title: String
    
    // MARK: - Geometry
    
    /// The bounds of the window in screen coordinates (top-left origin).
    let bounds: CGRect
    
    // MARK: - Window State
    
    /// The window layer (0 is normal, higher numbers are floating/menus).
    let layer: Int
    
    /// The alpha transparency of the window (0.0 to 1.0).
    let alpha: Float
    
    /// Whether the window is currently visible on screen.
    let isOnScreen: Bool
    
    // MARK: - Derived Classifications
    
    /// Categorises the owning application based on its bundle ID/name.
    var appCategory: AppCategory {
        let name = ownerName.lowercased()
        
        if name.contains("code") || name.contains("xcode") || name.contains("intellij") || name.contains("studio") {
            return .ide
        } else if name.contains("terminal") || name.contains("warp") || name.contains("iterm") {
            return .terminal
        } else if name.contains("safari") || name.contains("chrome") || name.contains("edge") || name.contains("arc") || name.contains("brave") {
            return .browser
        } else if name.contains("slack") || name.contains("discord") || name.contains("messages") {
            return .communication
        } else {
            return .standard
        }
    }
    
    /// Determines the semantic type of the window based on its metadata.
    var semanticType: SemanticRegionType {
        // Special case: Menu Bar
        if layer == Int(kCGMainMenuWindowLevel) || (ownerName == "Window Server" && title == "Menubar") {
            return .menuBar
        }
        
        // Special case: Dock
        if ownerName == "Dock" && (title == "Dock" || layer > 0) {
            return .dock
        }
        
        // Popups, tooltips, and floating menus usually have high layers
        if layer >= Int(kCGPopUpMenuWindowLevel) {
            return .popup
        }
        if layer >= Int(kCGFloatingWindowLevel) {
            return .floatingWindow
        }
        
        return .window
    }
}

// MARK: - AppCategory

/// Broad categorisation of macOS applications.
enum AppCategory: String, Sendable {
    case ide = "IDE"
    case terminal = "Terminal"
    case browser = "Browser"
    case communication = "Communication"
    case standard = "Standard Application"
}
