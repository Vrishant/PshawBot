// PipelineCoordinator.swift
// PshawBot
//
// The central orchestrator that pulls frames from the queue, runs all detectors
// concurrently, fuses their results into a SceneGraph, and publishes it to the UI.

import Foundation
import CoreGraphics
import OSLog
import SwiftUI

// MARK: - PipelineCoordinator

/// Orchestrates the entire semantic understanding pipeline.
///
/// This actor subscribes to the `FrameQueue`, processes each frame through
/// all enabled vision/AX stages, builds the semantic tree, and updates
/// the app state with the final result.
@Observable
@MainActor
final class PipelineCoordinator {
    
    // MARK: - Dependencies
    
    private let appState: AppState
    private let overlayController: OverlayWindowController
    
    // Sub-modules
    private let windowDetector = WindowDetector()
    private let axScanner = AccessibilityScanner()
    private let layoutDetector = VisionLayoutDetector()
    private let ocrEngine = OCREngine()
    private let uiDetector = UIElementDetector()
    private let iconDetector = IconDetector()
    private let treeBuilder = SemanticTreeBuilder()
    private let changeTracker = ChangeTracker()
    private let devModeClassifier = DeveloperModeClassifier()
    private let textBlockDetector = TextBlockDetector()
    
    // MARK: - State
    
    private var pipelineTask: Task<Void, Never>?
    private var previousGraph: SceneGraph?
    
    /// The latest fully processed semantic graph.
    private(set) var latestGraph: SceneGraph?
    
    /// The diff between the latest graph and the previous one.
    private(set) var latestDiff: SceneGraphDiff?
    
    /// The most recently detected text blocks, if any.
    private(set) var detectedBlocks: [DetectedTextBlock] = []
    
    private let logger = Logger(subsystem: "com.pshawbot", category: "Pipeline")
    
    // MARK: - Initialisation
    
    init(appState: AppState, overlayController: OverlayWindowController) {
        self.appState = appState
        self.overlayController = overlayController
    }
    
    // MARK: - Lifecycle
    
    /// Starts a lightweight loop that only updates the latest frame image
    /// for the Live Preview (no heavy analysis). Analysis is triggered on-demand
    /// via `snapToCurrentFrame()`.
    func start() {
        guard pipelineTask == nil else { return }
        
        pipelineTask = Task {
            logger.info("Pipeline coordinator started (snapshot mode)")
            
            // Only consume frames to keep the live image updated
            for await frame in await appState.frameQueue.frames {
                if Task.isCancelled { break }
                
                // Just update the displayed frame — no analysis
                self.appState.latestFrame = frame
            }
            
            logger.info("Pipeline coordinator stopped")
        }
    }
    
    func stop() {
        pipelineTask?.cancel()
        pipelineTask = nil
    }
    
    /// Flushes the frame queue, grabs the very latest frame, and runs
    /// the full analysis pipeline on it. Called when the user clicks "Snap".
    func snapToCurrentFrame() {
        Task {
            logger.info("Snap: flushing queue and analyzing current frame")
            
            // Clear stale blocks from previous snap
            self.detectedBlocks = []
            
            // Flush stale frames
            await appState.frameQueue.flush()
            
            // Wait briefly for a fresh frame to arrive
            try? await Task.sleep(for: .milliseconds(350))
            
            // Use whichever frame we have now
            guard let frame = appState.latestFrame, frame.cgImage != nil else {
                logger.warning("Snap: no frame available")
                return
            }
            
            let start = CACurrentMediaTime()
            
            do {
                try await processFrame(frame)
            } catch {
                logger.error("Snap analysis failed: \(error.localizedDescription)")
            }
            
            let duration = (CACurrentMediaTime() - start) * 1000
            logger.info("Snap: frame \(frame.id) analyzed in \(Int(duration))ms")
        }
    }
    
    /// Runs a focused, fast text block detection pass on the current frame.
    /// Only runs OCR + TextBlockDetector — no full pipeline.
    func detectTextBlocks() {
        Task {
            self.detectedBlocks = []
            
            guard let frame = appState.latestFrame, let image = frame.cgImage else {
                logger.warning("detectTextBlocks: no frame available")
                return
            }
            
            logger.info("Running focused text block detection")
            let displayBounds = CoordinateConverter.primaryDisplayBounds
            
            // Run OCR on the full frame
            let ocrBlocks = (try? await ocrEngine.recognizeText(in: image, within: displayBounds)) ?? []
            
            // Detect text blocks
            let blocks = await textBlockDetector.detect(
                in: image,
                ocrBlocks: ocrBlocks,
                displayBounds: displayBounds
            )
            
            self.detectedBlocks = blocks
            
            logger.info("Detected \(blocks.count) text blocks")
        }
    }
    
    // MARK: - Pipeline Execution

    
    /// Processes a single captured frame through all enabled stages.
    private func processFrame(_ frame: CapturedFrame) async throws {
        // Need a CGImage for visual analysis
        guard let image = frame.cgImage else {
            logger.debug("Skipping frame \(frame.id) — no CGImage")
            return
        }
        
        let displayBounds = CoordinateConverter.primaryDisplayBounds
        
        // 1. OS-Level Detection (Fast)
        var windows: [DetectedWindow] = []
        if appState.enabledStages.contains(.windowDetection) {
            windows = await windowDetector.detectWindows()
        }
        
        // 2. Concurrent Analysis (AX + Vision + OCR)
        // We use a TaskGroup to run heavy analysis stages in parallel.
        
        async let axTrees = scanAccessibility(for: windows)
        async let layoutRegions = detectLayout(in: image, bounds: displayBounds)
        async let ocrBlocks = recognizeText(in: image, bounds: displayBounds)
        
        // Await all parallel results
        let (axResult, rawRegions, rawText) = await (axTrees, try layoutRegions, try ocrBlocks)
        
        // 3. Heuristic Refinements
        var refinedRegions = rawRegions
        if appState.enabledStages.contains(.iconDetection) {
            refinedRegions = await iconDetector.filterIcons(from: refinedRegions)
        }
        if appState.enabledStages.contains(.uiElementDetection) {
            refinedRegions = await uiDetector.inferElements(from: refinedRegions, textBlocks: rawText)
        }
        
        // 4. Graph Fusion
        var sceneGraph = await treeBuilder.buildGraph(
            frameID: frame.id,
            timestamp: frame.timestamp,
            windows: windows,
            axTrees: axResult,
            visionRegions: refinedRegions,
            ocrText: rawText
        )
        
        // 5. Developer Mode Classification
        if appState.enabledStages.contains(.developerMode) && appState.isDeveloperModeEnabled {
            sceneGraph = await devModeClassifier.classify(sceneGraph)
        }
        
        // 6. Change Tracking
        let diff = await changeTracker.computeDiff(from: previousGraph, to: sceneGraph)
        
        // 7. Publish Results
        // This is safe because we are on the MainActor
        self.previousGraph = sceneGraph
        self.latestGraph = sceneGraph
        self.latestDiff = diff
        
        // 8. Update Overlay
        if appState.isOverlayVisible {
            overlayController.show(content: OverlayView(
                graph: sceneGraph,
                isInteractive: appState.isDeveloperModeEnabled // For now, use dev mode as interactive flag
            ))
        } else {
            overlayController.hide()
        }
    }
    
    // MARK: - Stage Wrappers
    
    private func scanAccessibility(for windows: [DetectedWindow]) async -> [CGWindowID: AXNode] {
        guard appState.enabledStages.contains(.accessibilityScanning) else { return [:] }
        
        var results: [CGWindowID: AXNode] = [:]
        
        // Use a task group to scan windows concurrently
        await withTaskGroup(of: (CGWindowID, AXNode?).self) { group in
            for window in windows {
                group.addTask {
                    let axTree = await self.axScanner.scan(window: window)
                    return (window.id, axTree)
                }
            }
            
            for await (id, tree) in group {
                if let tree = tree {
                    results[id] = tree
                }
            }
        }
        
        return results
    }
    
    private func detectLayout(in image: CGImage, bounds: CGRect) async throws -> [DetectedRegion] {
        guard appState.enabledStages.contains(.layoutDetection) else { return [] }
        return try await layoutDetector.detectRegions(in: image, within: bounds)
    }
    
    private func recognizeText(in image: CGImage, bounds: CGRect) async throws -> [RecognizedText] {
        guard appState.enabledStages.contains(.ocr) else { return [] }
        // For performance, we should ideally crop the image to specific windows,
        // but for Phase 1 we'll pass the full screen.
        return try await ocrEngine.recognizeText(in: image, within: bounds)
    }
}
