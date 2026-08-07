// DebugCaptureView.swift
// PshawBot
//
// A development-only view that proves the capture pipeline is working.
// Displays the most recently captured frame alongside real-time diagnostics.
//
// This view will be replaced by the full Inspector panel in Phase 6,
// but serves as the primary verification tool for Phases 1–4.

import SwiftUI
import OSLog

// MARK: - DebugCaptureView

/// A debug view showing the live captured screen frame and pipeline diagnostics.
///
/// This is the "frames are flowing" verification view for Phase 1.
/// It renders the latest captured frame at a reduced size and shows
/// real-time statistics about the capture pipeline.
struct DebugCaptureView: View {
    @Environment(AppState.self) private var appState
    
    /// Timer-driven refresh for queue stats (since they live in an actor).
    @State private var queueStats: FrameQueueStats?
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: captured frame preview
            framePreview
                .frame(maxWidth: .infinity)
            
            // Right: diagnostics panel
            diagnosticsPanel
                .frame(width: 280)
        }
    }
    
    // MARK: - Frame Preview
    
    @ViewBuilder
    private var framePreview: some View {
        ZStack {
            Color.black.opacity(0.3)
            
            if let frame = appState.latestFrame, let cgImage = frame.cgImage {
                Image(decorative: cgImage, scale: frame.scaleFactor)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 12)
                    .padding(20)
                    .transition(.opacity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "display")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.15))
                    
                    if !appState.captureManager.isCapturing {
                        Text("Press ▶ to start capturing")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                        
                        Button {
                            Task { await appState.toggleCapture() }
                        } label: {
                            Label("Start Capture", systemImage: "play.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.cyan.opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(.cyan.opacity(0.3), lineWidth: 1)
                                        )
                                )
                                .foregroundStyle(.cyan)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Waiting for first frame…")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.3))
                        
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.cyan)
                    }
                }
            }
        }
    }
    
    // MARK: - Diagnostics Panel
    
    @ViewBuilder
    private var diagnosticsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Label("Diagnostics", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                
                Divider().overlay(Color.white.opacity(0.06))
                
                // Capture Status
                diagnosticSection("Capture") {
                    diagnosticRow("Status", value: appState.captureManager.isCapturing ? "Active" : "Inactive",
                                  color: appState.captureManager.isCapturing ? .green : .red)
                    diagnosticRow("Permission", value: appState.captureManager.hasPermission ? "Granted" : "Denied",
                                  color: appState.captureManager.hasPermission ? .green : .red)
                    diagnosticRow("Display", value: appState.captureManager.displayInfo)
                    diagnosticRow("Target FPS", value: "\(appState.analysisFrameRate)")
                }
                
                // Frame Stats
                diagnosticSection("Frames") {
                    diagnosticRow("Captured", value: "\(appState.captureManager.framesCaptured)")
                    
                    if let frame = appState.latestFrame {
                        diagnosticRow("Latest ID", value: "#\(frame.id)")
                        diagnosticRow("Resolution", value: "\(Int(frame.size.width))×\(Int(frame.size.height))")
                        diagnosticRow("Scale", value: "\(frame.scaleFactor)x")
                        diagnosticRow("Complete", value: frame.isComplete ? "Yes" : "No",
                                      color: frame.isComplete ? .green : .orange)
                        diagnosticRow("Changed", value: frame.contentChanged ? "Yes" : "No")
                    }
                }
                
                // Queue Stats
                if let stats = queueStats {
                    diagnosticSection("Queue") {
                        diagnosticRow("Buffered", value: "\(stats.currentCount)/\(stats.capacity)")
                        diagnosticRow("Total Received", value: "\(stats.totalReceived)")
                        diagnosticRow("Total Dropped", value: "\(stats.totalDropped)",
                                      color: stats.totalDropped > 0 ? .orange : .white)
                        diagnosticRow("Drop Rate", value: String(format: "%.1f%%", stats.dropRate * 100),
                                      color: stats.dropRate > 0.1 ? .red : .white)
                    }
                }
                
                // Error display
                if let error = appState.captureManager.lastError {
                    diagnosticSection("Errors") {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer()
            }
            .padding(16)
        }
        .background(.ultraThinMaterial.opacity(0.2))
        .overlay(
            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(width: 1),
            alignment: .leading
        )
        .task {
            while !Task.isCancelled {
                let stats = await appState.frameQueue.stats
                self.queueStats = stats
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    
    // MARK: - Diagnostic Helpers
    
    @ViewBuilder
    private func diagnosticSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.2)
            
            content()
        }
    }
    
    @ViewBuilder
    private func diagnosticRow(_ label: String, value: String, color: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(color.opacity(0.8))
        }
    }
}
