# PshawBot — Workflow

How the pieces fit together and how data flows through the app at the current point in development.

## 1. Runtime Overview

PshawBot is a SwiftUI menu-bar app (`LSUIElement = false` in development, so a Dock icon is shown) that captures the screen, builds a semantic understanding of what is visible, and lets the user interact with the extracted code through an AI assistant.

```
ScreenCaptureManager ──► FrameQueue ──► PipelineCoordinator ──► SceneGraph ──► UI
   (ScreenCaptureKit)      (buffer)        (analysis)          (semantic      (LivePreview,
                                            & snap)             tree)          Inspector, Overlay)
                                                            ▲
                                            AppleIntelligenceService ◄──── ChatView
                                            GeminiService (legacy)
```

## 2. Launch Sequence

1. `PshawBotApp` (`App/PshawBotApp.swift`) is the `@main` entry point. It creates a shared `AppState` and an `OverlayWindowController`.
2. The main window's `.onAppear` builds a `PipelineCoordinator(appState:overlayController:)` and calls `coordinator.start()`, then `appState.onAppLaunch()` which requests Screen Recording permission.
3. `AppState` (`App/AppState.swift`) is the single source of truth. It owns:
   - `FrameQueue` (capacity 3) — the frame buffer.
   - `ScreenCaptureManager` — the capture engine wired to the queue.
   - UI state: `isOverlayVisible`, `isInspectorVisible`, `isDeveloperModeEnabled`.
   - Pipeline config: `analysisFrameRate` (default 4 FPS) and the enabled `PipelineStage` set.

## 3. Capture Flow

- `ScreenCaptureManager` (`ScreenCapture/ScreenCaptureManager.swift`) uses `ScreenCaptureKit` to stream desktop frames at the configured FPS into the `FrameQueue`.
- `FrameQueue` (`ScreenCapture/FrameQueue.swift`) keeps the newest frames and drops stale ones to avoid memory bloat.
- The `PipelineCoordinator`'s lightweight `start()` loop consumes frames purely to keep `appState.latestFrame` fresh for the Live Preview — **no heavy analysis runs continuously**; analysis is snapshot-based.

## 4. Analysis Pipeline (Snapshot Mode)

Analysis is triggered on demand via the **Snap** button in the Live Preview → `coordinator.snapToCurrentFrame()`:

1. **Flush & grab** — the frame queue is flushed, a fresh frame is awaited, then processed.
2. **Window Detection** — `WindowDetector` maps active windows via `CGWindowListCopyWindowInfo` (`Vision/WindowDetector.swift`).
3. **Concurrent analysis** (parallel via `async let` / `withTaskGroup`):
   - **Accessibility** — `AccessibilityScanner` probes the `AXUIElement` tree per window (`Vision/AccessibilityScanner.swift`).
   - **Layout** — `VisionLayoutDetector` groups UI/text elements into spatial containers (`LayoutDetection/VisionLayoutDetector.swift`).
   - **OCR** — `OCREngine` runs Apple Vision text recognition over the frame (`OCR/OCREngine.swift`).
4. **Heuristic refinements** — `IconDetector.filterIcons` and `UIElementDetector.inferElements` clean up detected regions (each stage individually toggleable).
5. **Graph fusion** — `SemanticTreeBuilder.buildGraph` fuses windows + AX trees + refined vision regions + OCR text into a `SceneGraph` (`SemanticGraph/`).
6. **Developer mode** — if enabled, `DeveloperModeClassifier` marks the window as a coding environment, and `CodePanelDetector` / `TextBlockDetector` / `CodeLexer` isolate the code editor pane (`DeveloperMode/`).
7. **Change tracking** — `ChangeTracker` diffs the new graph against the previous one (`SemanticGraph/ChangeTracker.swift`).
8. **Publish** — the graph, diff, and detected text blocks are stored on the coordinator and pushed to the overlay.

A separate `detectTextBlocks()` pass runs a fast OCR + `TextBlockDetector` only (used by the Snap/extract action).

## 5. Data Model

- `CapturedFrame`, `DetectedWindow`, `DetectedRegion`, `RecognizedText`, `SemanticRegionType` (`Models/`) — typed payloads flowing through the pipeline.
- `SceneGraph` (root), `SemanticNode` (entities), `SceneGraphDiff` — the fused semantic tree.
- `DetectedTextBlock` — grouped code blocks produced by `TextBlockDetector`.

## 6. AI Assistant

The chat layer is provider-agnostic via `AIServiceProtocol` (`Services/AIServiceProtocol.swift`).

- **AppleIntelligenceService** (default, active) — `Services/AppleIntelligenceService.swift`. Uses Apple's `FoundationModels` `LanguageModelSession` (macOS 26+, on-device, no API key). It maintains its own transcript and answers via `sendCode(_:language:userPrompt:)`.
- **GeminiService** (legacy/inactive) — `Services/GeminiService.swift`. REST client for Google's Gemini API; key entered in the chat UI and stored in `UserDefaults`. Currently unused (logger category: "GeminiService (inactive)").

Flow: user clicks **Snap** → code is extracted → user asks a question in `ChatView` → `ChatView` calls `aiService.sendCode(...)` → the assistant replies with analysis (approach, complexity, improvements).

## 7. UI Surfaces

- **Main window** (`ContentView`): segmented "Live Preview" / "Semantic Tree" tabs; custom title bar with display picker and capture toggle.
- **Menu bar extra**: Start/Stop capture, overlay & inspector toggles, display selection, frame/FPS stats, Developer Mode toggle, Settings, Quit. Keyboard shortcuts: ⌘⇧R / ⌘⇧O / ⌘⇧I.
- **Overlay**: `OverlayWindowController` + `OverlayView` draw bounding boxes on the desktop (click-through).
- **Inspector**: `InspectorPanel` is a UI-tree inspector for the `SceneGraph`.
- **Settings**: analysis FPS and per-`PipelineStage` toggles (`SettingsView`).

## 8. Permissions

- **Screen Recording** — requested at launch; required for capture (`NSScreenCaptureUsageDescription`).
- **Accessibility** — used by `AccessibilityScanner` for enhanced UI detection (`NSAccessibilityUsageDescription`).

## 9. Development Workflow

- `project.yml` is the source of truth for targets/settings. Structural changes are made there, then `xcodegen generate` regenerates `PshawBot.xcodeproj` (committed).
- Build: `xcodebuild -project PshawBot.xcodeproj -scheme PshawBot -configuration Debug build`
- Tests live in `PshawBotTests/` (OCR, FrameQueue, CoordinateConverter, AccessibilityScanner, WindowDetector).