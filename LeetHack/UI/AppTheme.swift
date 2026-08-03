// AppTheme.swift
// LeetHack
//
// Centralised design tokens and styles for the application's glassmorphism UI.

import SwiftUI

// MARK: - AppTheme

/// Centralised design tokens for the LeetHack UI.
enum AppTheme {
    
    // MARK: - Materials
    
    /// The standard frosted glass material for overlay backgrounds.
    static let glassMaterial: Material = .ultraThinMaterial
    
    /// The material for active/hovered elements.
    static let activeGlassMaterial: Material = .thinMaterial
    
    // MARK: - Colors
    
    /// Dark gradient background for main windows.
    static let windowBackground = LinearGradient(
        colors: [
            Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)),
            Color(nsColor: NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Accent color for primary actions.
    static let primaryAccent = Color.cyan
    
    /// Gradient for primary branding elements.
    static let brandGradient = LinearGradient(
        colors: [.cyan, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // MARK: - Geometry
    
    /// Standard corner radius for floating chips and buttons.
    static let cornerRadiusSmall: CGFloat = 6.0
    
    /// Standard corner radius for region overlays and panels.
    static let cornerRadiusMedium: CGFloat = 12.0
    
    /// Standard corner radius for large windows.
    static let cornerRadiusLarge: CGFloat = 16.0
    
    // MARK: - Animations
    
    /// Default animation for layout changes (snappy but smooth).
    static let layoutAnimation: Animation = .spring(response: 0.4, dampingFraction: 0.8)
    
    /// Animation for hover effects.
    static let hoverAnimation: Animation = .easeInOut(duration: 0.15)
    
    // MARK: - Typography
    
    static let monoFont = Font.system(size: 11, design: .monospaced)
    static let labelFont = Font.system(size: 12, weight: .medium, design: .rounded)
    
    // MARK: - Semantic Colors
    
    /// Returns the UI color for a given semantic region type based on its category.
    static func color(for regionType: SemanticRegionType) -> Color {
        return regionType.uiCategory.color
    }
}
