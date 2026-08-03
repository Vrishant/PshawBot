// LivePreviewView.swift
// LeetHack
//
// Live preview of captured screen. Shows the "Snap to Current" button and,
// after detection, highlights the code panel with a prominent YOLO-style
// overlay plus an extracted code card.

import SwiftUI

struct LivePreviewView: View {
    @Environment(AppState.self) private var appState
    let graph: SceneGraph
    let codePanel: DetectedCodePanel?
    let onSnap: () -> Void
    let onDetectCode: () -> Void
    
    @State private var hoveredNodeID: UUID?
    @State private var isSnapping: Bool = false
    @State private var isDetecting: Bool = false
    @State private var showCodeCard: Bool = true
    
    @StateObject private var geminiService = GeminiService()
    @State private var showChat: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            if let frame = appState.latestFrame, let cgImage = frame.cgImage {
                let displayBounds = CGDisplayBounds(frame.displayID)
                let displayPointWidth = displayBounds.width > 0 ? displayBounds.width : frame.size.width
                let displayPointHeight = displayBounds.height > 0 ? displayBounds.height : frame.size.height
                
                let scale = min(geo.size.width / displayPointWidth, geo.size.height / displayPointHeight)
                let scaledWidth = displayPointWidth * scale
                let scaledHeight = displayPointHeight * scale
                let xOffset = (geo.size.width - scaledWidth) / 2
                let yOffset = (geo.size.height - scaledHeight) / 2
                
                ZStack(alignment: .topLeading) {
                    // 1. Screen image
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .frame(width: scaledWidth, height: scaledHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // 2. Code panel highlight (primary)
                    if let panel = codePanel {
                        CodePanelOverlay(
                            panel: panel,
                            scale: scale,
                            displayOrigin: displayBounds.origin
                        )
                    }
                    
                    // 3. Bottom toolbar
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            snapButton
                            detectCodeButton
                            Spacer()
                            if let panel = codePanel {
                                codePanelBadge(panel: panel)
                            }
                        }
                        .padding(16)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .frame(width: scaledWidth, height: scaledHeight)
                }
                .offset(x: xOffset, y: yOffset)
                
                // 4. Code card (floating right side)
                if showCodeCard, let panel = codePanel, !panel.codeLines.isEmpty {
                    CodeExtractCard(panel: panel, isVisible: $showCodeCard, geminiService: geminiService, showChat: $showChat)
                        .frame(maxWidth: 320)
                        .offset(x: showChat ? geo.size.width - 760 : geo.size.width - 340, y: 12)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showChat)
                }
                
                // 5. Chat Side Panel
                if showChat {
                    HStack(spacing: 0) {
                        Spacer()
                        ChatView(
                            geminiService: geminiService,
                            codeContext: codePanel?.codeText,
                            language: codePanel?.language,
                            onClose: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showChat = false } }
                        )
                        .frame(width: 400)
                        .background(Color(NSColor.windowBackgroundColor))
                        .shadow(color: .black.opacity(0.3), radius: 20, x: -5, y: 0)
                        .transition(.move(edge: .trailing))
                    }
                    .zIndex(2)
                }
                
            } else {
                // No frame captured yet
                VStack(spacing: 20) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 52))
                        .foregroundStyle(.white.opacity(0.2))
                    
                    Text("No frame yet")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    HStack(spacing: 12) {
                        snapButton
                        detectCodeButton
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }
    
    // MARK: - Sub-views
    
    @ViewBuilder
    private var snapButton: some View {
        Button {
            isSnapping = true
            onSnap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isSnapping = false }
        } label: {
            HStack(spacing: 6) {
                if isSnapping {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    Image(systemName: "camera.aperture")
                }
                Text(isSnapping ? "Analyzing…" : "Snap")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2)))
            )
        }
        .buttonStyle(.plain)
        .disabled(isSnapping)
    }
    
    @ViewBuilder
    private var detectCodeButton: some View {
        Button {
            isDetecting = true
            showCodeCard = true
            onDetectCode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { isDetecting = false }
        } label: {
            HStack(spacing: 6) {
                if isDetecting {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    Image(systemName: "curlybraces.square.fill")
                }
                Text(isDetecting ? "Detecting…" : "Find Code")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.linearGradient(
                        colors: [Color(hue: 0.6, saturation: 0.8, brightness: 0.9),
                                 Color(hue: 0.55, saturation: 0.9, brightness: 0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .shadow(color: Color(hue: 0.6, saturation: 0.8, brightness: 0.9).opacity(0.4), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDetecting)
    }
    
    @ViewBuilder
    private func codePanelBadge(panel: DetectedCodePanel) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hue: 0.38, saturation: 0.8, brightness: 0.8))
                .frame(width: 8, height: 8)
                .shadow(color: .green.opacity(0.6), radius: 4)
            
            if let lang = panel.language {
                Text(lang)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Text("· \(panel.codeLines.count) lines")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5))
        .clipShape(Capsule())
    }
}

// MARK: - CodePanelOverlay

/// The bright YOLO-style box that highlights the detected code panel on screen.
private struct CodePanelOverlay: View {
    let panel: DetectedCodePanel
    let scale: CGFloat
    let displayOrigin: CGPoint
    
    private var scaledRect: CGRect {
        CGRect(
            x: (panel.bounds.minX - displayOrigin.x) * scale,
            y: (panel.bounds.minY - displayOrigin.y) * scale,
            width: panel.bounds.width * scale,
            height: panel.bounds.height * scale
        )
    }
    
    private let panelColor = Color(hue: 0.6, saturation: 0.85, brightness: 0.95)
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Outer glow
            RoundedRectangle(cornerRadius: 4)
                .stroke(panelColor.opacity(0.5), lineWidth: 4)
                .blur(radius: 4)
            
            // Main border
            RoundedRectangle(cornerRadius: 4)
                .stroke(panelColor, lineWidth: 2)
            
            // Subtle fill
            RoundedRectangle(cornerRadius: 4)
                .fill(panelColor.opacity(0.05))
            
            // Corner markers (YOLO style)
            CornerMarkers(color: panelColor, size: 14, thickness: 2.5)
            
            // Label chip
            HStack(spacing: 5) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 10, weight: .bold))
                Text("Code Panel")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                if let lang = panel.language {
                    Text("·")
                        .foregroundStyle(panelColor.opacity(0.6))
                    Text(lang)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                Spacer()
                Text("\(String(format: "%.0f%%", panel.confidence * 100))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(panelColor.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(panelColor.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            .offset(x: 0, y: -22)
        }
        .frame(width: scaledRect.width, height: scaledRect.height)
        .position(x: scaledRect.midX, y: scaledRect.midY)
    }
}

// MARK: - CornerMarkers

private struct CornerMarkers: View {
    let color: Color
    let size: CGFloat
    let thickness: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                // Top-left
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size))
                    p.addLine(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: size, y: 0))
                }.stroke(color, lineWidth: thickness)
                
                // Top-right
                Path { p in
                    p.move(to: CGPoint(x: w - size, y: 0))
                    p.addLine(to: CGPoint(x: w, y: 0))
                    p.addLine(to: CGPoint(x: w, y: size))
                }.stroke(color, lineWidth: thickness)
                
                // Bottom-left
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h - size))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: size, y: h))
                }.stroke(color, lineWidth: thickness)
                
                // Bottom-right
                Path { p in
                    p.move(to: CGPoint(x: w - size, y: h))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: w, y: h - size))
                }.stroke(color, lineWidth: thickness)
            }
        }
    }
}

// MARK: - CodeExtractCard

/// Floating card showing the extracted code text with syntax-like formatting.
private struct CodeExtractCard: View {
    let panel: DetectedCodePanel
    @Binding var isVisible: Bool
    
    @ObservedObject var geminiService: GeminiService
    @Binding var showChat: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "curlybraces.square.fill")
                    .foregroundStyle(Color(hue: 0.6, saturation: 0.8, brightness: 0.95))
                
                Text(panel.language ?? "Code")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                
                Spacer()
                
                Text("\(panel.codeLines.count) lines")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                
                Button {
                    withAnimation(.spring(duration: 0.2)) { isVisible = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hue: 0.6, saturation: 0.4, brightness: 0.25))
            
            Divider().background(Color.white.opacity(0.1))
            
            // Code lines
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(panel.codeLines.prefix(40).enumerated()), id: \.offset) { idx, line in
                        HStack(alignment: .top, spacing: 8) {
                            // Line number
                            Text("\(idx + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(width: 24, alignment: .trailing)
                            
                            // Code
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(lineColor(line))
                                .lineLimit(2)
                                .truncationMode(.tail)
                            
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 1)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 300)
            
            // Toolbar
            HStack {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showChat.toggle()
                    }
                } label: {
                    Label("Ask Gemini", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                Spacer()
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(panel.codeText, forType: .string)
                } label: {
                    Label("Copy Code", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(10)
            }
            .background(Color(hue: 0.6, saturation: 0.4, brightness: 0.2))
        }
        .background(Color(hue: 0.6, saturation: 0.35, brightness: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hue: 0.6, saturation: 0.5, brightness: 0.5).opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 16, y: 4)
    }
    
    private func lineColor(_ line: String) -> Color {
        let keywords = ["class", "public", "private", "int", "void", "return",
                        "string", "bool", "let", "var", "func", "def", "if",
                        "else", "for", "while", "struct", "enum", "const",
                        "static", "new", "import", "include"]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Comments
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*") {
            return Color(hue: 0.32, saturation: 0.4, brightness: 0.65)
        }
        
        // Keywords
        let first = trimmed.components(separatedBy: " ").first?.lowercased() ?? ""
        if keywords.contains(first) {
            return Color(hue: 0.58, saturation: 0.7, brightness: 0.95)
        }
        
        return .white.opacity(0.85)
    }
}
