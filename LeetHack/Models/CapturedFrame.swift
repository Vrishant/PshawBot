// CapturedFrame.swift
// LeetHack
//
// A value type representing a single captured screen frame.
// Designed for efficient passing through the async pipeline — the heavy
// IOSurface/CGImage data is lazily derived from the original CMSampleBuffer.

import CoreGraphics
import CoreMedia
import Foundation
import IOSurface
import ScreenCaptureKit
import CoreImage

// MARK: - CapturedFrame

/// A lightweight wrapper around a single screen capture frame.
///
/// `CapturedFrame` is the currency of the capture pipeline. It flows from
/// `ScreenCaptureManager` → `FrameQueue` → downstream analysis stages.
///
/// The struct stores the raw `CMSampleBuffer` and lazily derives a `CGImage`
/// only when a consumer actually needs pixel data. This avoids expensive
/// conversions for frames that are dropped due to back-pressure.
struct CapturedFrame: Identifiable, Sendable {
    
    // MARK: - Identity
    
    /// Monotonically increasing frame identifier.
    let id: UInt64
    
    /// The timestamp when this frame was captured, derived from the sample buffer's
    /// presentation timestamp.
    let timestamp: Date
    
    /// The presentation timestamp from the sample buffer, useful for precise timing.
    let presentationTimestamp: CMTime
    
    // MARK: - Display Metadata
    
    /// The display from which this frame was captured (for multi-monitor setups).
    let displayID: CGDirectDisplayID
    
    /// The pixel dimensions of the captured frame.
    let size: CGSize
    
    /// The scale factor of the display (e.g. 2.0 for Retina).
    let scaleFactor: CGFloat
    
    // MARK: - Frame Status
    
    /// Whether this frame represents a complete, displayable image.
    /// Incomplete frames (e.g. during display blanking) should be skipped.
    let isComplete: Bool
    
    /// Whether the screen content changed since the previous frame.
    /// When `false`, downstream stages can skip re-analysis entirely.
    let contentChanged: Bool
    
    // MARK: - Pixel Data
    
    /// The underlying `IOSurface` for zero-copy GPU access.
    /// This is the most efficient way to pass frame data to Metal or CoreML.
    let surface: IOSurface?
    
    /// The `CGImage` representation of this frame.
    /// Extracted from the sample buffer on first access.
    let cgImage: CGImage?
    
    // MARK: - Initialisation
    
    /// Creates a `CapturedFrame` from a `CMSampleBuffer` received by the
    /// `SCStreamOutput` delegate.
    ///
    /// - Parameters:
    ///   - sampleBuffer: The raw sample buffer from ScreenCaptureKit.
    ///   - frameID: A monotonically increasing identifier assigned by the `FrameQueue`.
    ///   - displayID: The CG display ID of the source display.
    ///   - scaleFactor: The display's backing scale factor.
    init(
        sampleBuffer: CMSampleBuffer,
        frameID: UInt64,
        displayID: CGDirectDisplayID,
        scaleFactor: CGFloat
    ) {
        self.id = frameID
        self.displayID = displayID
        self.scaleFactor = scaleFactor
        
        // Extract presentation timestamp
        self.presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        self.timestamp = Date()
        
        // Extract frame status from attachments
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let attachment = attachments.first {
            let status = attachment[.status] as? Int
            self.isComplete = (status == SCFrameStatus.complete.rawValue)
            
            if let dirtyRects = attachment[.dirtyRects] as? [CGRect] {
                self.contentChanged = !dirtyRects.isEmpty
            } else {
                self.contentChanged = true
            }
        } else {
            self.isComplete = false
            self.contentChanged = false
        }
        
        // Extract IOSurface for zero-copy access
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            self.surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
            
            // Derive size from pixel buffer dimensions
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            self.size = CGSize(width: width, height: height)
        } else {
            self.surface = nil
            self.size = .zero
        }
        
        // Create CGImage from the sample buffer
        // This is relatively cheap when backed by an IOSurface
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext(options: [.useSoftwareRenderer: false])
            self.cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        } else {
            self.cgImage = nil
        }
    }
    
    /// Creates a placeholder frame for testing or error states.
    static func placeholder(id: UInt64 = 0) -> CapturedFrame {
        CapturedFrame(
            id: id,
            timestamp: Date(),
            presentationTimestamp: .zero,
            displayID: CGMainDisplayID(),
            size: .zero,
            scaleFactor: 1.0,
            isComplete: false,
            contentChanged: false,
            surface: nil,
            cgImage: nil
        )
    }
    
    /// Returns a copy of the frame with a new identifier.
    func withID(_ newID: UInt64) -> CapturedFrame {
        CapturedFrame(
            id: newID,
            timestamp: timestamp,
            presentationTimestamp: presentationTimestamp,
            displayID: displayID,
            size: size,
            scaleFactor: scaleFactor,
            isComplete: isComplete,
            contentChanged: contentChanged,
            surface: surface,
            cgImage: cgImage
        )
    }
    
    /// Private memberwise initialiser for internal use (e.g. `placeholder`).
    private init(
        id: UInt64,
        timestamp: Date,
        presentationTimestamp: CMTime,
        displayID: CGDirectDisplayID,
        size: CGSize,
        scaleFactor: CGFloat,
        isComplete: Bool,
        contentChanged: Bool,
        surface: IOSurface?,
        cgImage: CGImage?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.presentationTimestamp = presentationTimestamp
        self.displayID = displayID
        self.size = size
        self.scaleFactor = scaleFactor
        self.isComplete = isComplete
        self.contentChanged = contentChanged
        self.surface = surface
        self.cgImage = cgImage
    }
}

// MARK: - SCFrameStatus Bridge

/// Maps ScreenCaptureKit's frame status values to a Swift-friendly enum.
/// We define this separately because `SCFrameStatus` is only available in the
/// ScreenCaptureKit module and we want `CapturedFrame` to be self-contained.
enum SCFrameStatus: Int, Sendable {
    case complete = 0
    case idle = 1
    case blank = 2
    case suspended = 3
    case started = 4
}

// MARK: - CustomStringConvertible

extension CapturedFrame: CustomStringConvertible {
    var description: String {
        "Frame(\(id), \(Int(size.width))×\(Int(size.height)), " +
        "complete: \(isComplete), changed: \(contentChanged))"
    }
}
