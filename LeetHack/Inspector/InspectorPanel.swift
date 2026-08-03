// InspectorPanel.swift
// LeetHack
//
// Developer inspection panel showing the real-time semantic tree data.

import SwiftUI
import OSLog

// MARK: - InspectorPanel

/// A SwiftUI view that provides a deep dive into the system's current understanding
/// of the screen. Displays the full `SceneGraph` as an outline list.
struct InspectorPanel: View {
    
    let graph: SceneGraph?
    let diff: SceneGraphDiff?
    let captureStats: FrameQueueStats?
    
    @State private var searchText = ""
    @State private var expandedNodes: Set<UUID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Semantic Inspector")
                    .font(.headline)
                
                Spacer()
                
                if let stats = captureStats {
                    Text("\(stats.currentCount)/\(stats.capacity) buf")
                        .font(AppTheme.monoFont)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search regions, text...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .padding(12)
            
            Divider()
            
            // Tree View
            if let graph = graph {
                List {
                    let rootNodes = filteredRootNodes(from: graph)
                    
                    if rootNodes.isEmpty {
                        Text("No regions found")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(rootNodes) { node in
                            NodeRow(
                                node: node,
                                graph: graph,
                                diff: diff,
                                expandedNodes: $expandedNodes,
                                indentLevel: 0
                            )
                        }
                    }
                }
                .listStyle(.inset)
                // Remove the default background so our dark gradient shows through
                .scrollContentBackground(.hidden)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Waiting for semantic graph...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 350, minHeight: 500)
    }
    
    // MARK: - Filtering
    
    private func filteredRootNodes(from graph: SceneGraph) -> [SemanticNode] {
        if searchText.isEmpty {
            // If no search, return true root nodes
            return graph.rootNodes
        } else {
            // If searching, flatten and filter all nodes
            let query = searchText.lowercased()
            return graph.allNodes.filter { node in
                node.type.rawValue.lowercased().contains(query) ||
                (node.recognizedText?.lowercased().contains(query) ?? false) ||
                (node.metadata.values.contains { $0.lowercased().contains(query) })
            }
        }
    }
}

// MARK: - NodeRow

/// A single row in the inspector tree view. Handles its own children recursively.
fileprivate struct NodeRow: View {
    let node: SemanticNode
    let graph: SceneGraph
    let diff: SceneGraphDiff?
    
    @Binding var expandedNodes: Set<UUID>
    let indentLevel: Int
    
    private var isExpanded: Bool {
        expandedNodes.contains(node.id)
    }
    
    private var children: [SemanticNode] {
        graph.children(of: node.id)
    }
    
    private var hasChildren: Bool {
        !children.isEmpty
    }
    
    private var isAdded: Bool {
        diff?.added.contains(node.id) ?? false
    }
    
    private var isModified: Bool {
        diff?.modified.contains(node.id) ?? false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The row itself
            HStack(spacing: 8) {
                // Indentation
                Spacer().frame(width: CGFloat(indentLevel * 16))
                
                // Disclosure triangle
                if hasChildren {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .onTapGesture {
                            withAnimation(AppTheme.layoutAnimation) {
                                if isExpanded {
                                    expandedNodes.remove(node.id)
                                } else {
                                    expandedNodes.insert(node.id)
                                }
                            }
                        }
                } else {
                    Spacer().frame(width: 12)
                }
                
                // Icon
                Image(systemName: node.type.iconName)
                    .foregroundStyle(AppTheme.color(for: node.type))
                    .frame(width: 16)
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(node.type.rawValue)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        
                        if isAdded {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.3))
                                .cornerRadius(4)
                        } else if isModified {
                            Text("MOD")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.3))
                                .cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        Text("\(Int(node.confidence * 100))%")
                            .font(AppTheme.monoFont)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let text = node.recognizedText, !text.isEmpty {
                        Text(text)
                            .font(AppTheme.monoFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    
                    if !node.metadata.isEmpty {
                        Text(node.metadata.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
                            .font(AppTheme.monoFont)
                            .foregroundStyle(.cyan.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.001)) // Make tap target full width
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(Color.white.opacity(0.1))
            
            // Children
            if isExpanded && hasChildren {
                ForEach(children) { child in
                    NodeRow(
                        node: child,
                        graph: graph,
                        diff: diff,
                        expandedNodes: $expandedNodes,
                        indentLevel: indentLevel + 1
                    )
                }
            }
        }
    }
}
