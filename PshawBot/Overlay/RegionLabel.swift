// RegionLabel.swift
// PshawBot
//
// A small glassmorphism chip that displays the type and confidence of a detected region.

import SwiftUI

// MARK: - RegionLabel

/// A compact, glassmorphism label chip shown on the top-left of each detected region
/// in the overlay.
struct RegionLabel: View {
    
    let node: SemanticNode
    let isHovered: Bool
    
    private var baseColor: Color {
        AppTheme.color(for: node.type)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: node.type.iconName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
            
            Text(node.type.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            
            if isHovered || node.depth == 0 {
                if let text = node.recognizedText, !text.isEmpty {
                    Text("- \(text)")
                        .font(.system(size: 9, weight: .medium, design: .default))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 200, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(baseColor)
        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
        .animation(.snappy, value: isHovered)
    }
}
