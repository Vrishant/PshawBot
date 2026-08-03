// LeetHackApp.swift
// LeetHack
//
// The main entry point for the LeetHack macOS application.
//
// Architecture:
// - Uses SwiftUI's @main App lifecycle.
// - Creates a menu bar extra (NSStatusItem) as the primary interaction point.
// - The main window shows a debug capture view during Phase 1.
// - The overlay and inspector windows will be added in Phase 6.
//
// The app runs as a "menu bar utility" — it lives in the menu bar and
// optionally shows windows for inspection. It does NOT appear in the Dock
// by default (controlled via Info.plist LSUIElement).

import SwiftUI
import OSLog

// MARK: - LeetHackApp

@main
struct LeetHackApp: App {
    
    /// The root application state, shared across all views.
    @State private var appState = AppState()
    
    /// The overlay window manager.
    @StateObject private var overlayController = OverlayWindowController()
    
    /// The pipeline orchestrator.
    @State private var pipelineCoordinator: PipelineCoordinator?
    
    /// Logger for app lifecycle events.
    private let logger = Logger(subsystem: "com.leethack", category: "App")
    
    var body: some Scene {
        
        // MARK: - Main Window
        
        // The primary development/debug window.
        Window("LeetHack Inspector", id: "main") {
            ContentView(pipelineCoordinator: pipelineCoordinator)
                .environment(appState)
                .onAppear {
                    Task {
                        // Setup pipeline
                        let coordinator = PipelineCoordinator(appState: appState, overlayController: overlayController)
                        pipelineCoordinator = coordinator
                        coordinator.start()
                        
                        await appState.onAppLaunch()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        
        // MARK: - Menu Bar Extra
        
        // The persistent menu bar icon.
        MenuBarExtra("LeetHack", systemImage: "eye.trianglebadge.exclamationmark") {
            MenuBarContent()
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)
        
        // MARK: - Settings Window
        
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

// MARK: - MenuBarContent

/// The dropdown menu content for the menu bar extra.
struct MenuBarContent: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        // Capture toggle
        Button {
            Task { await appState.toggleCapture() }
        } label: {
            Label(
                appState.captureManager.isCapturing ? "Stop Capture" : "Start Capture",
                systemImage: appState.captureManager.isCapturing ? "stop.circle" : "play.circle"
            )
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        
        Divider()
        
        // Overlay toggle
        Button {
            appState.toggleOverlay()
        } label: {
            Label(
                appState.isOverlayVisible ? "Hide Overlay" : "Show Overlay",
                systemImage: appState.isOverlayVisible ? "eye.slash" : "eye"
            )
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .disabled(!appState.captureManager.isCapturing)
        
        // Inspector toggle
        Button {
            appState.toggleInspector()
        } label: {
            Label(
                appState.isInspectorVisible ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.right"
            )
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        
        Divider()
        
        // Display selection
        Menu {
            Picker("Display", selection: Binding(
                get: { appState.captureManager.selectedDisplayID },
                set: { appState.captureManager.selectedDisplayID = $0 }
            )) {
                Text("None").tag(CGDirectDisplayID?.none)
                ForEach(Array(appState.captureManager.availableDisplays.enumerated()), id: \.element.displayID) { index, display in
                    Text("Screen \(index + 1) (\(display.width)×\(display.height))").tag(Optional(display.displayID))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(appState.captureManager.selectedDisplayID == nil ? "Display: None" : appState.captureManager.displayInfo, systemImage: "display")
        }
        
        Divider()
        
        // Status info
        if appState.captureManager.isCapturing {
            Text("Frames: \(appState.captureManager.framesCaptured)")
                .font(.caption)
            Text("FPS: \(appState.analysisFrameRate)")
                .font(.caption)
        } else {
            Text("Capture inactive")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        
        if let error = appState.captureManager.lastError {
            Text("⚠️ \(error)")
                .font(.caption)
                .foregroundStyle(.red)
        }
        
        Divider()
        
        // Developer mode toggle
        Toggle("Developer Mode", isOn: Binding(
            get: { appState.isDeveloperModeEnabled },
            set: { appState.isDeveloperModeEnabled = $0 }
        ))
        
        Divider()
        
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)
        
        Button("Quit LeetHack") {
            Task {
                await appState.onAppTerminate()
                NSApplication.shared.terminate(nil)
            }
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

// MARK: - ContentView

/// The main window content view.
/// Shows the inspector panel and handles overlay visibility state.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    let pipelineCoordinator: PipelineCoordinator?
    
    @State private var selectedTab: Int = 0
    
    var body: some View {
        ZStack {
            // Background: dark gradient
            LinearGradient(
                colors: [
                    Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)),
                    Color(nsColor: NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Title bar area
                TitleBarView(selectedTab: $selectedTab)
                
                Divider()
                    .overlay(Color.white.opacity(0.06))
                
                // Main content
                if appState.captureManager.hasPermission {
                    if appState.isDebugViewVisible {
                        DebugCaptureView()
                    } else if let coordinator = pipelineCoordinator {
                        if selectedTab == 0 {
                            LivePreviewView(
                                graph: coordinator.latestGraph ?? SceneGraph(frameID: 0, timestamp: Date()),
                                codePanel: coordinator.detectedCodePanel,
                                onSnap: { coordinator.snapToCurrentFrame() },
                                onDetectCode: { coordinator.detectCodePanel() }
                            )
                        } else {
                            InspectorPanel(
                                graph: coordinator.latestGraph,
                                diff: coordinator.latestDiff,
                                captureStats: nil
                            )
                        }
                    } else {
                        ProgressView("Starting Pipeline...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    PermissionRequestView()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: appState.isOverlayVisible) { _, _ in
            // Overlay visibility is handled by PipelineCoordinator on next frame
        }
    }
}

// MARK: - TitleBarView

/// A custom title bar with app branding and capture controls.
struct TitleBarView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon and name
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.linearGradient(
                    colors: [.cyan, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            Text("LeetHack")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            
            Text("Screen Understanding")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
            
            Spacer()
            
            // Display Picker
            Menu {
                Picker("Display", selection: Binding(
                    get: { appState.captureManager.selectedDisplayID },
                    set: { appState.captureManager.selectedDisplayID = $0 }
                )) {
                    Text("None").tag(CGDirectDisplayID?.none)
                    ForEach(Array(appState.captureManager.availableDisplays.enumerated()), id: \.element.displayID) { index, display in
                        Text("Screen \(index + 1) (\(display.width)×\(display.height))").tag(Optional(display.displayID))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "display")
                    Text(appState.captureManager.selectedDisplayID == nil ? "None" : "Screen")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Spacer()
            
            Picker("", selection: $selectedTab) {
                Text("Live Preview").tag(0)
                Text("Semantic Tree").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.captureManager.isCapturing ? Color.green : Color.red.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .shadow(color: appState.captureManager.isCapturing ? .green.opacity(0.5) : .clear, radius: 4)
                
                Text(appState.captureManager.isCapturing ? "Capturing" : "Idle")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            
            // Capture toggle button
            Button {
                Task { await appState.toggleCapture() }
            } label: {
                Image(systemName: appState.captureManager.isCapturing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(appState.captureManager.isCapturing ? .red : .green)
            }
            .buttonStyle(.plain)
            .help(appState.captureManager.isCapturing ? "Stop capture" : "Start capture")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.3))
    }
}

// MARK: - PermissionRequestView

/// Shown when screen recording permission has not been granted.
struct PermissionRequestView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(
                    colors: [.cyan.opacity(0.7), .blue.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            
            Text("Screen Recording Permission Required")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            
            Text("LeetHack needs screen recording permission to\nunderstand what's on your display.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            
            Button {
                Task { await appState.captureManager.requestPermission() }
            } label: {
                Text("Grant Permission")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.linearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            
            if let error = appState.captureManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
                    .padding(.top, 8)
            }
            
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
            .foregroundStyle(.cyan.opacity(0.7))
            
            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Settings View

/// Placeholder settings view — will be expanded in later phases.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        Form {
            Section("Capture") {
                Picker("Analysis FPS", selection: Binding(
                    get: { appState.analysisFrameRate },
                    set: { appState.analysisFrameRate = $0 }
                )) {
                    Text("1 FPS").tag(1)
                    Text("2 FPS").tag(2)
                    Text("4 FPS").tag(4)
                    Text("8 FPS").tag(8)
                }
                .pickerStyle(.segmented)
            }
            
            Section("Pipeline Stages") {
                ForEach(PipelineStage.allCases) { stage in
                    Toggle(isOn: Binding(
                        get: { appState.enabledStages.contains(stage) },
                        set: { enabled in
                            if enabled {
                                appState.enabledStages.insert(stage)
                            } else {
                                appState.enabledStages.remove(stage)
                            }
                        }
                    )) {
                        Label(stage.rawValue, systemImage: stage.iconName)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
    }
}
