// AppState.swift
// LeetHack
//
// The single source of truth for the application's global state.
// All major subsystems are initialised and wired together here.
//
// Design decisions:
// - @Observable (not ObservableObject) for fine-grained SwiftUI tracking.
// - Centralised ownership of all pipeline components to ensure proper
//   lifecycle management.
// - Publishes derived state that the UI needs (e.g. isOverlayVisible,
//   frameRate) without exposing internal implementation details.

import Foundation
import SwiftUI
import OSLog

// MARK: - AppState

/// The root application state that owns and coordinates all subsystems.
///
/// `AppState` is created once at app launch and passed through the SwiftUI
/// environment. It owns:
/// - The screen capture pipeline (ScreenCaptureManager + FrameQueue)
/// - Pipeline configuration (frame rate, enabled stages)
/// - UI state (overlay visibility, inspector visibility)
///
/// Subsystems for Vision, OCR, SemanticGraph, etc. will be added in
/// later phases.
@MainActor
@Observable
final class AppState {
    
    // MARK: - Pipeline Components
    
    /// The frame buffer connecting capture to analysis.
    let frameQueue: FrameQueue
    
    /// The screen capture engine.
    let captureManager: ScreenCaptureManager
    
    // MARK: - UI State
    
    /// Whether the glassmorphism overlay is currently visible.
    var isOverlayVisible: Bool = true
    
    /// Whether the developer inspector panel is open.
    var isInspectorVisible: Bool = true
    
    /// Whether developer mode (IDE-aware analysis) is enabled.
    var isDeveloperModeEnabled: Bool = true
    
    // MARK: - Pipeline Configuration
    
    /// Target analysis frame rate (FPS).
    /// This is distinct from the overlay render rate (always 60 FPS).
    var analysisFrameRate: Int = 4 {
        didSet {
            captureManager.targetFPS = analysisFrameRate
        }
    }
    
    /// Which pipeline stages are currently enabled.
    /// Disabling stages reduces CPU usage at the cost of less detailed analysis.
    var enabledStages: Set<PipelineStage> = Set(PipelineStage.allCases)
    
    // MARK: - Debug / Diagnostics
    
    /// The most recently captured frame, for debug display.
    var latestFrame: CapturedFrame?
    
    /// The most recent pipeline error message.
    var lastPipelineError: String?
    
    /// Whether the debug capture view is visible (development only).
    var isDebugViewVisible: Bool = false
    
    // MARK: - Lifecycle
    
    /// Logger for app-level events.
    private let logger = Logger(subsystem: "com.leethack", category: "AppState")
    
    // MARK: - Initialisation
    
    init() {
        let queue = FrameQueue(capacity: 3)
        self.frameQueue = queue
        self.captureManager = ScreenCaptureManager(frameQueue: queue)
        
        logger.info("AppState initialised")
    }
    
    // MARK: - Lifecycle Methods
    
    /// Called when the app finishes launching.
    /// Requests permissions.
    func onAppLaunch() async {
        logger.info("App launching — requesting permissions")
        await captureManager.requestPermission()
    }
    
    /// Called when the app is about to terminate.
    /// Stops capture and cleans up resources.
    func onAppTerminate() async {
        logger.info("App terminating — cleaning up")
        await captureManager.stopCapture()
        await frameQueue.terminate()
    }
    
    // MARK: - Actions
    
    /// Toggles screen capture on/off.
    func toggleCapture() async {
        await captureManager.toggleCapture()
    }
    
    /// Toggles the overlay visibility.
    func toggleOverlay() {
        isOverlayVisible.toggle()
    }
    
    /// Toggles the inspector panel.
    func toggleInspector() {
        isInspectorVisible.toggle()
    }
}

// MARK: - PipelineStage

/// The stages of the analysis pipeline that can be individually toggled.
enum PipelineStage: String, CaseIterable, Identifiable, Sendable {
    case windowDetection = "Window Detection"
    case accessibilityScanning = "Accessibility Scanning"
    case ocr = "OCR"
    case layoutDetection = "Layout Detection"
    case iconDetection = "Icon Detection"
    case uiElementDetection = "UI Element Detection"
    case embeddings = "Vision Embeddings"
    case developerMode = "Developer Mode"
    
    var id: String { rawValue }
    
    /// SF Symbol name for this stage.
    var iconName: String {
        switch self {
        case .windowDetection: return "macwindow.on.rectangle"
        case .accessibilityScanning: return "accessibility"
        case .ocr: return "text.viewfinder"
        case .layoutDetection: return "rectangle.3.group"
        case .iconDetection: return "app.badge.checkmark"
        case .uiElementDetection: return "cursorarrow.click.2"
        case .embeddings: return "brain.head.profile"
        case .developerMode: return "chevron.left.forwardslash.chevron.right"
        }
    }
}
