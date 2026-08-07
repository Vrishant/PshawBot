// OverlayWindowController.swift
// PshawBot
//
// Manages the transparent NSWindow that floats above the OS to display the overlay.

import Cocoa
import SwiftUI
import OSLog

// MARK: - OverlayWindowController

/// Controls the transparent, click-through overlay window.
///
/// This window uses `NSWindow.Level.floating` to stay above standard apps,
/// and `collectionBehavior` to span all desktop spaces.
@MainActor
final class OverlayWindowController: ObservableObject {
    
    private var window: NSWindow?
    private let logger = Logger(subsystem: "com.pshawbot", category: "OverlayWindowController")
    
    /// Whether the overlay currently accepts mouse events (Option key held down).
    @Published var isInteractive: Bool = false
    
    init() {}
    
    /// Shows the overlay with the given SwiftUI view content.
    func show<Content: View>(content: Content) {
        if window == nil {
            createWindow()
        }
        
        guard let window = window else { return }
        
        let hostingView = NSHostingView(rootView: content)
        // Ensure the hosting view doesn't paint a background
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        
        logger.info("Overlay window shown")
    }
    
    /// Hides the overlay window.
    func hide() {
        window?.orderOut(nil)
        logger.info("Overlay window hidden")
    }
    
    /// Toggles the click-through behaviour.
    /// - Parameter interactive: If true, the user can click on the overlay elements.
    func setInteractive(_ interactive: Bool) {
        guard let window = window, isInteractive != interactive else { return }
        
        isInteractive = interactive
        window.ignoresMouseEvents = !interactive
        
        if interactive {
            // Slightly darken the screen to indicate interaction mode
            window.backgroundColor = NSColor.black.withAlphaComponent(0.1)
        } else {
            window.backgroundColor = .clear
        }
    }
    
    private func createWindow() {
        let displayBounds = CoordinateConverter.primaryDisplayBounds
        
        // Convert to bottom-left coordinates for AppKit
        let appKitBounds = CoordinateConverter.topLeftToBottomLeft(displayBounds, displayHeight: displayBounds.height)
        
        let window = NSWindow(
            contentRect: appKitBounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Critical settings for a full-screen overlay
        window.level = .floating // Above normal windows, below screen saver/menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        
        // By default, let mouse events pass through to the apps underneath
        window.ignoresMouseEvents = true
        
        self.window = window
    }
}
