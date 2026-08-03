// CoordinateConverter.swift
// LeetHack
//
// Utility for converting between different macOS coordinate systems.
//
// macOS has multiple coordinate systems that all disagree on where (0,0) is:
// - AppKit / Core Graphics: origin at bottom-left of primary display
// - ScreenCaptureKit: origin at top-left of primary display
// - Vision framework: normalised 0–1, origin at bottom-left
// - AXUIElement: origin at top-left of primary display
//
// This utility provides conversions between all of them.

import Foundation
import CoreGraphics

// MARK: - CoordinateConverter

/// Converts coordinates between macOS display, Vision framework, and
/// accessibility coordinate systems.
///
/// All public methods are static — this is a pure utility with no state.
enum CoordinateConverter {
    
    // MARK: - Screen Coordinates
    
    /// The total bounds of the primary display.
    /// This is cached because display configuration rarely changes.
    static var primaryDisplayBounds: CGRect {
        CGRect(
            origin: .zero,
            size: CGSize(
                width: CGFloat(CGDisplayPixelsWide(CGMainDisplayID())),
                height: CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
            )
        )
    }
    
    /// Converts a `CGRect` from top-left origin (ScreenCaptureKit / AX)
    /// to bottom-left origin (AppKit / Vision pixel space).
    ///
    /// - Parameters:
    ///   - rect: The rectangle in top-left coordinate space.
    ///   - displayHeight: The height of the display in pixels.
    /// - Returns: The rectangle in bottom-left coordinate space.
    static func topLeftToBottomLeft(
        _ rect: CGRect,
        displayHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: displayHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
    
    /// Converts a `CGRect` from bottom-left origin (AppKit) to top-left
    /// origin (ScreenCaptureKit / AX).
    ///
    /// - Parameters:
    ///   - rect: The rectangle in bottom-left coordinate space.
    ///   - displayHeight: The height of the display in pixels.
    /// - Returns: The rectangle in top-left coordinate space.
    static func bottomLeftToTopLeft(
        _ rect: CGRect,
        displayHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: displayHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
    
    // MARK: - Vision Framework Coordinates
    
    /// Converts a normalised Vision framework bounding box to pixel coordinates.
    ///
    /// Vision framework uses normalised coordinates (0–1) with origin at
    /// bottom-left. This converts to top-left pixel coordinates matching
    /// the ScreenCaptureKit / AX coordinate system.
    ///
    /// - Parameters:
    ///   - normalizedRect: The Vision framework bounding box (0–1 range).
    ///   - imageSize: The pixel dimensions of the source image.
    /// - Returns: The bounding box in top-left pixel coordinates.
    static func visionToScreen(
        normalizedRect: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        // Vision: origin at bottom-left, normalised 0–1
        // Screen: origin at top-left, pixel coordinates
        let x = normalizedRect.origin.x * imageSize.width
        let y = (1.0 - normalizedRect.origin.y - normalizedRect.height) * imageSize.height
        let width = normalizedRect.width * imageSize.width
        let height = normalizedRect.height * imageSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    /// Converts pixel coordinates (top-left origin) to Vision framework
    /// normalised coordinates.
    ///
    /// - Parameters:
    ///   - pixelRect: The bounding box in top-left pixel coordinates.
    ///   - imageSize: The pixel dimensions of the image.
    /// - Returns: The normalised bounding box for use with Vision requests.
    static func screenToVision(
        pixelRect: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        let x = pixelRect.origin.x / imageSize.width
        let y = 1.0 - (pixelRect.origin.y + pixelRect.height) / imageSize.height
        let width = pixelRect.width / imageSize.width
        let height = pixelRect.height / imageSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - Window-Relative Coordinates
    
    /// Converts a screen-space rectangle to window-relative coordinates.
    ///
    /// - Parameters:
    ///   - screenRect: The rectangle in screen coordinates (top-left origin).
    ///   - windowBounds: The window's bounds in screen coordinates.
    /// - Returns: The rectangle relative to the window's origin, or `nil` if
    ///   the rectangle doesn't intersect the window.
    static func screenToWindow(
        screenRect: CGRect,
        windowBounds: CGRect
    ) -> CGRect? {
        let intersection = screenRect.intersection(windowBounds)
        guard !intersection.isNull else { return nil }
        
        return CGRect(
            x: intersection.origin.x - windowBounds.origin.x,
            y: intersection.origin.y - windowBounds.origin.y,
            width: intersection.width,
            height: intersection.height
        )
    }
    
    /// Converts a window-relative rectangle to screen coordinates.
    ///
    /// - Parameters:
    ///   - windowRect: The rectangle relative to the window's origin.
    ///   - windowBounds: The window's bounds in screen coordinates.
    /// - Returns: The rectangle in screen coordinates (top-left origin).
    static func windowToScreen(
        windowRect: CGRect,
        windowBounds: CGRect
    ) -> CGRect {
        CGRect(
            x: windowRect.origin.x + windowBounds.origin.x,
            y: windowRect.origin.y + windowBounds.origin.y,
            width: windowRect.width,
            height: windowRect.height
        )
    }
    
    // MARK: - Intersection / Containment
    
    /// Calculates the Intersection over Union (IoU) between two rectangles.
    ///
    /// IoU is used to determine if two detected regions refer to the same
    /// physical area of the screen. Values close to 1.0 indicate near-perfect
    /// overlap; values close to 0.0 indicate distinct regions.
    ///
    /// - Parameters:
    ///   - a: First rectangle.
    ///   - b: Second rectangle.
    /// - Returns: IoU value between 0.0 and 1.0.
    static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea
        
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
    
    /// Checks whether rectangle `inner` is substantially contained within `outer`.
    ///
    /// - Parameters:
    ///   - inner: The potentially contained rectangle.
    ///   - outer: The potentially containing rectangle.
    ///   - threshold: Minimum fraction of `inner`'s area that must be inside
    ///     `outer` (default: 0.8 = 80%).
    /// - Returns: `true` if `inner` is at least `threshold` contained.
    static func isContained(
        _ inner: CGRect,
        within outer: CGRect,
        threshold: CGFloat = 0.8
    ) -> Bool {
        let intersection = inner.intersection(outer)
        guard !intersection.isNull else { return false }
        
        let innerArea = inner.width * inner.height
        guard innerArea > 0 else { return false }
        
        let containedArea = intersection.width * intersection.height
        return containedArea / innerArea >= threshold
    }
}
