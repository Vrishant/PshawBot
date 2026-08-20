# PshawBot — Changes

Project change log and a snapshot of how everything works together at the current point.

## Changelog

All notable changes are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) loosely.

### [0.1.0] — 2026-08-20 (Initial Point)

Repo hygiene & metadata alignment before the public push.

**Added**
- `.gitignore` covering macOS, Xcode, SwiftPM, CocoaPods/Carthage, editor and local-secret artifacts.
- `WORKFLOW.md` — up-to-date runtime workflow of the project.

**Changed**
- `project.yml`: `xcodeVersion` bumped to 26.0; test target deployment raised to macOS 26.0.
- `Info.plist`: display name and permission strings renamed from LeetHack to **PshawBot**; `LSMinimumSystemVersion` set to 26.0.
- `README.md`: updated to macOS 26 / Xcode 26 requirements, Apple Intelligence backend docs, XcodeGen (`project.yml`) usage, and added `TextBlockDetector` / `AIServiceProtocol` / `AppleIntelligenceService`.

**Removed**
- Tracked junk: `.DS_Store` files and Xcode `xcuserdata`/`*.xcuserstate` artifacts.
- Stale `LeetHack.xcodeproj/` leftover from the pre-rename project.

### [0.1.0] — 2026-08-07 — Name Revamp & Apple AI

**Added**
- `Services/AIServiceProtocol.swift` — provider-agnostic chat contract (`ChatMessage`, `AIService`).
- `Services/AppleIntelligenceService.swift` — on-device AI via Apple `FoundationModels` (macOS 26+).
- `DeveloperMode/TextBlockDetector.swift` — groups OCR lines into code blocks.

**Changed**
- Project renamed from **LeetHack** to **PshawBot**: source tree, app entry (`PshawBotApp`), `PshawBot.xcodeproj`, scheme, and bundle loggers (`com.pshawbot.*`).
- AI assistant switched to Apple Intelligence as the active backend; Gemini kept as legacy.

### [0.1.0] — 2026-08-03 — First Commit

Initial LeetHack project.

**Added**
- Full foundation: `ScreenCaptureManager` + `FrameQueue` (ScreenCaptureKit), `OCREngine` (Vision), `WindowDetector` / `AccessibilityScanner` / `UIElementDetector` / `IconDetector`, `VisionLayoutDetector`, `SceneGraph` + `SemanticTreeBuilder` + `ChangeTracker`, `DeveloperMode` (classifier, code panel detector, code lexer), `GeminiService`, `PipelineCoordinator`, SwiftUI (`LivePreviewView`, `ChatView`, `DebugCaptureView`, `Overlay`, `InspectorPanel`), `EmbeddingEngine`, `CoordinateConverter`, unit tests, and XcodeGen `project.yml`.

## How Everything Works Together (Initial Point)

At this point the app is a **snapshot-based screen-understanding pipeline** with an on-device AI assistant:

1. **App launch** — `PshawBotApp` creates `AppState` (owns `FrameQueue` + `ScreenCaptureManager`), builds `PipelineCoordinator`, requests Screen Recording permission, and starts capture.
2. **Capture** — `ScreenCaptureManager` streams frames into the 3-slot `FrameQueue`; `PipelineCoordinator.start()` only keeps `latestFrame` fresh (no continuous heavy analysis).
3. **Snap analysis** — the user presses **Snap** (`snapToCurrentFrame`): the queue flushes, then a frame is analyzed through toggleable `PipelineStage`s — Window Detection, Accessibility scanning, OCR, Layout Detection, Icon/UI-Element heuristics — fused by `SemanticTreeBuilder` into a `SceneGraph`, optionally classified as developer mode and run through `CodePanelDetector`/`TextBlockDetector`/`CodeLexer` to extract code.
4. **Change tracking** — `ChangeTracker` diffs consecutive graphs to detect scrolling/UI changes.
5. **Publishing** — results update the `LivePreviewView`, `InspectorPanel`, and the desktop `Overlay`.
6. **AI** — extracted code is sent through `ChatView` to `AppleIntelligenceService` (`FoundationModels`, on-device, no API key). `GeminiService` remains available as a legacy REST fallback.
7. **UI surfaces** — main inspector window (Live Preview / Semantic Tree tabs), menu bar extra (capture, overlay, inspector, developer mode, settings), settings for FPS and per-stage toggles.

**Key design decisions at this point**
- `@Observable` (not `ObservableObject`) for fine-grained SwiftUI tracking.
- Analysis is on-demand (Snap) rather than continuous, trading always-on updates for CPU efficiency.
- AI is behind the thin `AIService` protocol so backends are swappable.
- The Xcode project is generated from `project.yml` via XcodeGen and the generated `.xcodeproj` is committed.