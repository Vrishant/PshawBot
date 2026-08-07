// ScreenCaptureManager.swift
// PshawBot
//
// Manages the macOS screen capture session using ScreenCaptureKit.
// This is the entry point of the entire vision pipeline — it configures
// an SCStream, receives CMSampleBuffers via the delegate callback, wraps
// them in CapturedFrame structs, and feeds them into the FrameQueue.
//
// Design decisions:
// - We capture the entire primary display rather than individual windows,
//   because we want to understand the full desktop composition.
// - Frame rate is configurable (default 4 FPS) — this is the analysis rate,
//   not the overlay render rate.
// - We use `@Observable` so SwiftUI views can react to state changes
//   (e.g. isCapturing, error messages, permission status).

import Foundation
import ScreenCaptureKit
import CoreMedia
import OSLog

// MARK: - ScreenCaptureManager

/// Manages the ScreenCaptureKit capture session.
///
/// This class is the sole owner of the `SCStream` and is responsible for:
/// - Requesting screen recording permission
/// - Enumerating available displays
/// - Configuring the capture stream (resolution, frame rate, pixel format)
/// - Receiving frames via `SCStreamOutput` and dispatching to `FrameQueue`
/// - Handling errors and stream interruptions
///
/// ## Thread Safety
/// The `SCStreamOutput` delegate methods are called on a background queue
/// managed by ScreenCaptureKit. We immediately dispatch frames to the
/// `FrameQueue` actor, which provides isolation.
@Observable
final class ScreenCaptureManager: NSObject, @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Target frames per second for the capture stream.
    /// This controls how often we receive new frames for analysis.
    /// The overlay renders independently at 60 FPS.
    var targetFPS: Int = 4 {
        didSet {
            guard targetFPS != oldValue, isCapturing else { return }
            Task { await reconfigureStream() }
        }
    }
    
    /// The scale factor for capture resolution relative to the native display.
    /// 1.0 = native resolution, 0.5 = half resolution (faster processing).
    var scaleFactor: CGFloat = 1.0
    
    // MARK: - State
    
    /// Whether the capture stream is currently running.
    private(set) var isCapturing: Bool = false
    
    /// Whether screen recording permission has been granted.
    private(set) var hasPermission: Bool = false
    
    /// The most recent error, if any.
    private(set) var lastError: String?
    
    /// Information about the currently captured display.
    private(set) var displayInfo: String = "No display"
    
    /// The number of frames captured in the current session.
    private(set) var framesCaptured: UInt64 = 0
    
    /// All available displays.
    private(set) var availableDisplays: [SCDisplay] = []
    
    /// The currently selected display ID, or nil if capture is disabled.
    var selectedDisplayID: CGDirectDisplayID? {
        didSet {
            guard selectedDisplayID != oldValue else { return }
            Task { await handleDisplaySelectionChanged() }
        }
    }
    
    // MARK: - Dependencies
    
    /// The frame queue that receives captured frames.
    let frameQueue: FrameQueue
    
    // MARK: - Private State
    
    /// The active capture stream.
    private var stream: SCStream?
    
    /// The content filter defining what to capture.
    private var contentFilter: SCContentFilter?
    
    /// The display ID currently being captured by the stream.
    private var currentCaptureDisplayID: CGDirectDisplayID = CGMainDisplayID()
    
    /// The available shareable content (displays, windows, apps).
    private var availableContent: SCShareableContent?
    
    /// The dispatch queue for receiving stream output.
    private let outputQueue = DispatchQueue(
        label: "com.pshawbot.screen-capture.output",
        qos: .userInitiated
    )
    
    /// Logger for this module.
    private let logger = Logger(
        subsystem: "com.pshawbot",
        category: "ScreenCapture"
    )
    
    // MARK: - Initialisation
    
    /// Creates a new `ScreenCaptureManager` with the specified frame queue.
    ///
    /// - Parameter frameQueue: The queue to dispatch captured frames into.
    init(frameQueue: FrameQueue) {
        self.frameQueue = frameQueue
        super.init()
    }
    
    // MARK: - Permission
    
    /// Checks and requests screen recording permission.
    ///
    /// On first call, this triggers the macOS permission dialog.
    /// Subsequent calls return the cached permission state.
    func requestPermission() async {
        do {
            // Attempting to enumerate shareable content triggers the permission prompt
            // if permission hasn't been granted yet.
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            availableContent = content
            availableDisplays = content.displays
            hasPermission = true
            lastError = nil
            
            // Default to first display if not already set
            if selectedDisplayID == nil, let first = content.displays.first {
                selectedDisplayID = first.displayID
            }
            
            if let display = content.displays.first(where: { $0.displayID == selectedDisplayID }) {
                displayInfo = "Display: \(display.width)×\(display.height)"
            }
            
            logger.info("Screen recording permission granted. Displays: \(content.displays.count)")
        } catch {
            hasPermission = false
            lastError = "Screen recording permission denied: \(error.localizedDescription)"
            logger.error("Permission error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Capture Lifecycle
    
    /// Starts the screen capture stream.
    ///
    /// This will capture the primary display at the configured frame rate
    /// and resolution. Frames are dispatched to the `frameQueue`.
    ///
    /// - Throws: If permission is not granted or the stream cannot be created.
    func startCapture() async throws {
        if !hasPermission {
            await requestPermission()
            if !hasPermission {
                throw CaptureError.permissionDenied
            }
        }
        
        guard !isCapturing else {
            logger.warning("Capture already running, ignoring startCapture()")
            return
        }
        
        // Refresh available content
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        availableContent = content
        availableDisplays = content.displays
        
        guard let displayID = selectedDisplayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            logger.info("No display selected or available. Stopping capture.")
            return
        }
        
        currentCaptureDisplayID = display.displayID
        displayInfo = "Display: \(display.width)×\(display.height)"
        
        // Create a filter to capture the entire display.
        // We exclude our own app's windows to avoid recursive capture.
        let excludedApps = content.applications.filter { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )
        contentFilter = filter
        
        // Configure the stream
        let config = SCStreamConfiguration()
        
        // Resolution: use display's native size scaled by our factor
        let width = Int(CGFloat(display.width) * scaleFactor)
        let height = Int(CGFloat(display.height) * scaleFactor)
        config.width = width
        config.height = height
        
        // Frame rate
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        
        // Pixel format: BGRA for compatibility with Vision and CoreML
        config.pixelFormat = kCVPixelFormatType_32BGRA
        
        // Show cursor in captures (useful for understanding user intent)
        config.showsCursor = true
        
        // Queue depth: ScreenCaptureKit's internal buffer
        config.queueDepth = 3
        
        // Create and start the stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        
        try await stream.startCapture()
        
        self.stream = stream
        isCapturing = true
        framesCaptured = 0
        lastError = nil
        
        logger.info("Capture started: \(width)×\(height) @ \(self.targetFPS) FPS")
    }
    
    /// Stops the screen capture stream.
    func stopCapture() async {
        guard isCapturing, let stream = stream else { return }
        
        do {
            try await stream.stopCapture()
        } catch {
            logger.error("Error stopping capture: \(error.localizedDescription)")
        }
        
        self.stream = nil
        isCapturing = false
        
        logger.info("Capture stopped. Total frames: \(self.framesCaptured)")
    }
    
    /// Toggles capture on/off.
    func toggleCapture() async {
        if isCapturing {
            await stopCapture()
        } else {
            do {
                try await startCapture()
            } catch {
                lastError = error.localizedDescription
                logger.error("Failed to start capture: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Reconfiguration
    
    private func handleDisplaySelectionChanged() async {
        if selectedDisplayID != nil {
            if isCapturing {
                await stopCapture()
                try? await startCapture()
            }
        } else {
            await stopCapture()
        }
    }
    
    /// Reconfigures the running stream with updated settings.
    /// This is called when `targetFPS` or `scaleFactor` changes.
    private func reconfigureStream() async {
        guard let stream = stream, isCapturing else { return }
        
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        
        if let display = availableContent?.displays.first {
            config.width = Int(CGFloat(display.width) * scaleFactor)
            config.height = Int(CGFloat(display.height) * scaleFactor)
        }
        
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 3
        
        do {
            try await stream.updateConfiguration(config)
            logger.info("Stream reconfigured: \(self.targetFPS) FPS")
        } catch {
            logger.error("Failed to reconfigure stream: \(error.localizedDescription)")
            lastError = "Reconfiguration failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureManager: SCStreamOutput {
    
    /// Called by ScreenCaptureKit on the `outputQueue` whenever a new frame
    /// is available.
    ///
    /// This method must be fast — we wrap the buffer and dispatch immediately.
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        // We only process screen frames, not audio
        guard type == .screen else { return }
        
        // Extract data synchronously on the delegate queue to avoid sending
        // non-Sendable CMSampleBuffer across actor boundaries.
        let tempFrame = CapturedFrame(
            sampleBuffer: sampleBuffer,
            frameID: 0,
            displayID: currentCaptureDisplayID,
            scaleFactor: scaleFactor
        )
        
        // Only enqueue complete frames with content
        guard tempFrame.isComplete else { return }
        
        // Dispatch the fully isolated Sendable frame
        Task {
            let frameID = await frameQueue.nextID()
            let finalFrame = tempFrame.withID(frameID)
            
            await frameQueue.enqueue(finalFrame)
            
            // Update counter on the main actor for UI observation
            await MainActor.run {
                self.framesCaptured += 1
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    
    /// Called when the stream encounters an error.
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Stream stopped with error: \(error.localizedDescription)")
        
        Task { @MainActor in
            self.isCapturing = false
            self.lastError = "Stream error: \(error.localizedDescription)"
        }
    }
}

// MARK: - CaptureError

/// Errors specific to the screen capture subsystem.
enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplayFound
    case streamCreationFailed(String)
    case alreadyCapturing
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission was not granted. Please enable it in System Settings → Privacy & Security → Screen Recording."
        case .noDisplayFound:
            return "No display found for capture."
        case .streamCreationFailed(let reason):
            return "Failed to create capture stream: \(reason)"
        case .alreadyCapturing:
            return "Screen capture is already running."
        }
    }
}
