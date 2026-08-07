// LivePreviewView.swift
// PshawBot
//
// Live preview of captured screen. Shows the "Snap to Current" button and,
// after detection, highlights text blocks with a prominent overlay plus a list card.

import SwiftUI

struct LivePreviewView: View {
    @Environment(AppState.self) private var appState
    let coordinator: PipelineCoordinator
    
    @State private var isSnapping: Bool = false
    @State private var isDetecting: Bool = false
    @State private var showBlocksList: Bool = true
    
    @State private var selectedBlockIDs: Set<UUID> = []
    
    @StateObject private var aiService = AppleIntelligenceService()
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
                    
                    // 2. Text blocks highlight
                    ForEach(coordinator.detectedBlocks) { block in
                        TextBlockOverlay(
                            block: block,
                            scale: scale,
                            displayOrigin: displayBounds.origin,
                            isSelected: selectedBlockIDs.contains(block.id)
                        )
                        .onTapGesture {
                            if selectedBlockIDs.contains(block.id) {
                                selectedBlockIDs.remove(block.id)
                            } else {
                                selectedBlockIDs.insert(block.id)
                            }
                        }
                    }
                    
                    // 3. Bottom toolbar
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            snapButton
                            detectCodeButton
                            Spacer()
                            if !coordinator.detectedBlocks.isEmpty {
                                blocksBadge
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
                
                // 4. Blocks List (floating right side)
                if showBlocksList, !coordinator.detectedBlocks.isEmpty {
                    BlocksListCard(
                        blocks: coordinator.detectedBlocks,
                        selectedIDs: $selectedBlockIDs,
                        isVisible: $showBlocksList,
                        aiService: aiService,
                        showChat: $showChat
                    )
                    .frame(width: 320)
                    .offset(x: showChat ? geo.size.width - 760 : geo.size.width - 340, y: 12)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showChat)
                }
                
                // 5. Chat Side Panel
                if showChat {
                    HStack(spacing: 0) {
                        Spacer()
                        let combinedContext = coordinator.detectedBlocks
                            .filter { selectedBlockIDs.contains($0.id) }
                            .map { "\($0.isCode ? "Code Block (\($0.language ?? "Unknown")):\n```\n\($0.text)\n```" : "Text Block:\n\($0.text)")" }
                            .joined(separator: "\n\n")
                            
                        ChatView(
                            aiService: aiService,
                            codeContext: combinedContext.isEmpty ? nil : combinedContext,
                            language: nil,
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
        .onChange(of: coordinator.detectedBlocks.count) {
            // Auto-select code blocks by default
            selectedBlockIDs = Set(coordinator.detectedBlocks.filter { $0.isCode }.map { $0.id })
            if selectedBlockIDs.isEmpty && !coordinator.detectedBlocks.isEmpty {
                // If no code, select the first block
                selectedBlockIDs = [coordinator.detectedBlocks[0].id]
            }
        }
    }
    
    // MARK: - Sub-views
    
    @ViewBuilder
    private var snapButton: some View {
        Button {
            isSnapping = true
            coordinator.snapToCurrentFrame()
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
            showBlocksList = true
            selectedBlockIDs = []
            coordinator.detectTextBlocks()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { isDetecting = false }
        } label: {
            HStack(spacing: 6) {
                if isDetecting {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    Image(systemName: "doc.text.viewfinder")
                }
                Text(isDetecting ? "Detecting…" : "Find Blocks")
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
    private var blocksBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .shadow(color: .blue.opacity(0.6), radius: 4)
            
            Text("\(coordinator.detectedBlocks.count) blocks")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            
            Text("· \(selectedBlockIDs.count) selected")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5))
        .clipShape(Capsule())
    }
}

// MARK: - TextBlockOverlay

private struct TextBlockOverlay: View {
    let block: DetectedTextBlock
    let scale: CGFloat
    let displayOrigin: CGPoint
    let isSelected: Bool
    
    private var scaledRect: CGRect {
        CGRect(
            x: (block.bounds.minX - displayOrigin.x) * scale,
            y: (block.bounds.minY - displayOrigin.y) * scale,
            width: block.bounds.width * scale,
            height: block.bounds.height * scale
        )
    }
    
    private var panelColor: Color {
        if isSelected {
            return block.isCode ? Color(hue: 0.6, saturation: 0.85, brightness: 0.95) : .green
        } else {
            return .gray.opacity(0.6)
        }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(panelColor.opacity(0.5), lineWidth: 4)
                    .blur(radius: 4)
            }
            
            RoundedRectangle(cornerRadius: 4)
                .stroke(panelColor, lineWidth: isSelected ? 2 : 1)
            
            RoundedRectangle(cornerRadius: 4)
                .fill(panelColor.opacity(isSelected ? 0.1 : 0.02))
            
            CornerMarkers(color: panelColor, size: 14, thickness: isSelected ? 2.5 : 1.5)
            
            // Label chip
            HStack(spacing: 5) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                
                if block.isCode {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 10, weight: .bold))
                } else {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(block.isCode ? (block.language ?? "Code") : "Text")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
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
        .contentShape(Rectangle()) // makes the whole box tappable
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
                Path { p in p.move(to: CGPoint(x: 0, y: size)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: size, y: 0)) }.stroke(color, lineWidth: thickness)
                Path { p in p.move(to: CGPoint(x: w - size, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: size)) }.stroke(color, lineWidth: thickness)
                Path { p in p.move(to: CGPoint(x: 0, y: h - size)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: size, y: h)) }.stroke(color, lineWidth: thickness)
                Path { p in p.move(to: CGPoint(x: w - size, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - size)) }.stroke(color, lineWidth: thickness)
            }
        }
    }
}

// MARK: - BlocksListCard

private struct BlocksListCard: View {
    let blocks: [DetectedTextBlock]
    @Binding var selectedIDs: Set<UUID>
    @Binding var isVisible: Bool
    
    @ObservedObject var aiService: AppleIntelligenceService
    @Binding var showChat: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundStyle(.white)
                
                Text("Extracted Blocks")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                
                Spacer()
                
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
            .background(Color.black.opacity(0.4))
            
            Divider().background(Color.white.opacity(0.1))
            
            // List of blocks
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    ForEach(blocks) { block in
                        Button {
                            if selectedIDs.contains(block.id) {
                                selectedIDs.remove(block.id)
                            } else {
                                selectedIDs.insert(block.id)
                            }
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selectedIDs.contains(block.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedIDs.contains(block.id) ? .blue : .gray)
                                    .font(.system(size: 16))
                                    .padding(.top, 2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        if block.isCode {
                                            Text(block.language ?? "Code")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.cyan)
                                        } else {
                                            Text("Text")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.gray)
                                        }
                                        Spacer()
                                        Text("\(block.codeLines.count) lines")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.gray)
                                    }
                                    Text(block.text.prefix(150).replacingOccurrences(of: "\n", with: " ") + (block.text.count > 150 ? "..." : ""))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .padding(8)
                            .background(Color.white.opacity(selectedIDs.contains(block.id) ? 0.08 : 0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedIDs.contains(block.id) ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 400)
            
            // Toolbar
            HStack {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showChat.toggle()
                    }
                } label: {
                    Label("Ask AI (\(selectedIDs.count))", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selectedIDs.isEmpty ? Color.gray.opacity(0.8) : Color.blue.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(selectedIDs.isEmpty)
                
                Spacer()
            }
            .background(Color.black.opacity(0.3))
            .padding(10)
        }
        .background(Color(hue: 0.6, saturation: 0.35, brightness: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hue: 0.6, saturation: 0.5, brightness: 0.5).opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 16, y: 4)
    }
}
