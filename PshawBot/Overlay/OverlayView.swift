// OverlayView.swift
// PshawBot
//
// Renders the scene graph as an interactive visual overlay on top of all windows.

import SwiftUI

// MARK: - OverlayView

/// Renders the `SceneGraph` as a series of glassmorphism bounding boxes.
///
/// This view is hosted in a transparent `NSWindow` that covers the entire screen.
/// It observes the `PipelineCoordinator`'s latest graph and animates changes.
struct OverlayView: View {
    
    let graph: SceneGraph
    let isInteractive: Bool
    
    @State private var hoveredNodeID: UUID?
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Invisible background to catch clicks if interactive
            if isInteractive {
                Color.white.opacity(0.01)
                    .ignoresSafeArea()
            }
            
            // We use ForEach over the nodes. SwiftUI will animate bounds changes
            // automatically because SemanticNode is Identifiable and Equatable.
            ForEach(graph.allNodes) { node in
                if isNodeVisible(node) {
                    RegionOverlayBox(
                        node: node,
                        isHovered: hoveredNodeID == node.id,
                        isInteractive: isInteractive
                    )
                    .onHover { hovering in
                        if isInteractive {
                            if hovering {
                                hoveredNodeID = node.id
                            } else if hoveredNodeID == node.id {
                                hoveredNodeID = nil
                            }
                        }
                    }
                }
            }
        }
        .animation(AppTheme.layoutAnimation, value: graph)
    }
    
    private func isNodeVisible(_ node: SemanticNode) -> Bool {
        if hoveredNodeID == node.id { return true }
        
        // Hide individual text blocks unless hovered to reduce visual clutter
        if node.type == .textBlock || node.type == .textInput {
            return false
        }
        
        // Only show structural elements with reasonable confidence
        return node.confidence > 0.3
    }
}

// MARK: - RegionOverlayBox

/// A single bounding box in the overlay.
fileprivate struct RegionOverlayBox: View {
    
    let node: SemanticNode
    let isHovered: Bool
    let isInteractive: Bool
    
    private var baseColor: Color {
        AppTheme.color(for: node.type)
    }
    
    private var opacity: Double {
        if isHovered { return 1.0 }
        return 0.8
    }
    
    private var borderWidth: CGFloat {
        if isHovered { return 2.5 }
        return node.depth == 0 ? 2.0 : 1.5
    }
    
    private var labelOffset: CGSize {
        // If box is at the very top of the screen, render label inside the box
        if node.bounds.minY < 18 {
            return CGSize(width: borderWidth / 2, height: borderWidth / 2)
        } else {
            return CGSize(width: -borderWidth / 2, height: -16)
        }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // The box itself
            Rectangle()
                .fill(baseColor.opacity(isHovered ? 0.15 : 0.02))
                .border(baseColor.opacity(opacity), width: borderWidth)
            
            // The YOLO label chip
            RegionLabel(node: node, isHovered: isHovered)
                .offset(labelOffset)
        }
        .frame(width: node.bounds.width, height: node.bounds.height)
        .position(x: node.bounds.midX, y: node.bounds.midY)
        // Ensure child nodes render on top of parents
        .zIndex(Double(node.depth) + (isHovered ? 100 : 0))
    }
}
