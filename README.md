# PshawBot

**Real-time screen understanding for macOS.**

PshawBot is a macOS desktop application that continuously observes your screen, constructs a semantic understanding of everything visible, and presents an interactive visual overlay showing its interpretation. It is purpose-built to recognize coding environments (like LeetCode), extract syntax-aware code, and provide AI assistance via Gemini.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1+) recommended
- Xcode 16.0+
- Screen Recording permission
- Accessibility permission (for enhanced UI detection)

## Building

### Prerequisites

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project:

```bash
brew install xcodegen
```

### Generate & Build

```bash
# Generate the Xcode project from project.yml
xcodegen generate

# Build from command line
xcodebuild -project PshawBot.xcodeproj -scheme PshawBot -configuration Debug build

# Or open in Xcode
open PshawBot.xcodeproj
```

## Architecture

PshawBot operates as a multi-stage data processing pipeline. It captures raw frames from the screen and progressively adds structural intelligence using a layered signal fusion approach:

1. **Capture**: `ScreenCaptureKit` streams desktop frames at high performance.
2. **Vision & OCR**: Native macOS Vision frameworks (`VNRecognizeTextRequest`) scan the image for UI elements and text.
3. **Accessibility**: `AXUIElement` probes the macOS accessibility tree to extract native application structures.
4. **Heuristics & Lexing**: Custom detectors group text clusters spatially. For code environments, a `CodeLexer` tracks bracket depths to extract perfect code blocks, filtering out UI noise.
5. **Semantic Scene Graph**: All signals are fused into a unified hierarchical tree representing the AI's understanding of the screen.
6. **Services & UI**: The `PipelineCoordinator` orchestrates the flow, updating a real-time SwiftUI `LivePreviewView`. Extracted code is sent to the `GeminiService` for AI analysis.

## Project Structure & File Roles

The codebase is organized by domain responsibility. Here is what each file does:

### `App/` — Entry point and global state
- `PshawBotApp.swift`: The `@main` entry point for the SwiftUI application.
- `AppState.swift`: Global observable state managing the latest captured frames and UI toggles.

### `ScreenCapture/` — macOS Screen Recording
- `ScreenCaptureManager.swift`: Wraps `ScreenCaptureKit` to request permissions and capture screen streams.
- `FrameQueue.swift`: Handles frame buffering and dropping to maintain performance without memory bloat.

### `Vision/` & `OCR/` — Native AI & Computer Vision
- `WindowDetector.swift`: Uses `CGWindowListCopyWindowInfo` to map out active window bounds on screen.
- `UIElementDetector.swift`: Uses Vision to find buttons, text fields, and standard UI shapes.
- `IconDetector.swift`: Identifies standard icons (like close, minimize, maximize buttons).
- `AccessibilityScanner.swift`: Probes the `AXUIElement` tree for rich structural metadata of native apps.
- `OCREngine.swift`: Wraps Apple's Vision text recognition to extract all readable strings from the screen.

### `LayoutDetection/` — Spatial Organization
- `VisionLayoutDetector.swift`: Groups individual UI and text elements into logical horizontal/vertical containers based on spatial proximity.
- `LayoutDetectorProtocol.swift`: Defines the interface for layout detection models.

### `SemanticGraph/` — The "Brain"
- `SceneGraph.swift`: The root container for the analyzed screen state.
- `SemanticNode.swift`: Represents a single entity on screen (a window, a button, a line of text).
- `SemanticTreeBuilder.swift`: Fuses Vision, OCR, and Accessibility data into the unified `SceneGraph` tree.
- `ChangeTracker.swift`: Diffs graphs between frames to detect scrolling or UI changes.

### `DeveloperMode/` — Coding Environment Intelligence
- `CodePanelDetector.swift`: Uses smart vertical clustering to identify the coding editor pane in browsers (like LeetCode), ignoring surrounding UI.
- `CodeLexer.swift`: A structural parser that extracts complete code blocks from noisy OCR output using bracket-depth tracking from an anchor (e.g., `class Solution`).
- `DeveloperModeClassifier.swift`: Determines if a given window is an IDE or coding environment.

### `Models/` — Core Data Structures
- `CapturedFrame.swift`, `DetectedWindow.swift`, `DetectedRegion.swift`, `RecognizedText.swift`, `SemanticRegionType.swift`: Strong type definitions for data flowing through the pipeline.

### `Services/` — Orchestration and APIs
- `PipelineCoordinator.swift`: The main loop coordinator. It receives frames, calls the detectors, builds the semantic graph, and extracts code panels.
- `GeminiService.swift`: Handles API communication with Google's Gemini LLM. Manages chat history, prompts, and streaming responses.

### `UI/` — Interactive Interface
- `LivePreviewView.swift`: The main visual interface. Renders the screen, draws YOLO-style overlay boxes around detected code, and handles the "Snap" actions.
- `ChatView.swift`: A sleek slide-out side panel for talking to Gemini, featuring native Markdown rendering and syntax-highlighted code blocks.
- `DebugCaptureView.swift`: A developer view for diagnosing raw OCR and Vision outputs.
- `AppTheme.swift`: Shared colors and visual styles.

### `Overlay/` & `Inspector/` — Debugging Tools
- `OverlayView.swift` & `OverlayWindowController.swift`: A transparent, click-through overlay window that draws bounding boxes directly on your desktop.
- `InspectorPanel.swift`: A UI tree inspector (similar to Xcode's view debugger) for the Semantic Graph.
- `RegionLabel.swift`: UI components for drawing labels on detected regions.

### `Embeddings/` & `Utilities/` — Helpers
- `EmbeddingEngine.swift`: Generates vector embeddings for visual regions.
- `CoordinateConverter.swift`: Translates coordinates between the screen's native resolution and the SwiftUI display view.

## Build Phases

| Phase | Status | Description |
|-------|--------|-------------|
| 1 | ✅ | Foundation & Screen Capture |
| 2 | ✅ | Window & Accessibility Detection |
| 3 | ✅ | OCR & Layout Detection |
| 4 | ✅ | Semantic Graph & Change Tracking |
| 5 | ✅ | Developer Mode, Lexer & Gemini API |
| 6 | ✅ | Live Preview, Overlays & Chat UI |

## License

Private — not for redistribution.
