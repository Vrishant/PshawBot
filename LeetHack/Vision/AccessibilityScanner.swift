// AccessibilityScanner.swift
// LeetHack
//
// Traverses the macOS Accessibility (AX) tree to discover UI structure.
// This is the primary source of truth for native applications.

import Foundation
import ApplicationServices
import OSLog

// MARK: - AccessibilityScanner

/// Scans the macOS accessibility tree for a given application to build a
/// structural hierarchy of its UI elements.
///
/// This provides rich metadata (buttons, text fields, groups, roles) for apps
/// that support the AX API natively (e.g. Safari, Xcode, Finder). It works
/// poorly for custom-rendered apps like Discord (Electron) or games.
@MainActor
final class AccessibilityScanner {
    
    // MARK: - Configuration
    
    /// Maximum depth to traverse the AX tree. Prevents infinite recursion
    /// or hanging on deeply nested UI structures. Reduced to 3 to colab blocks.
    let maxDepth: Int = 3
    
    /// Maximum time allowed for traversing a single window (prevents hanging).
    let timeoutSeconds: TimeInterval = 0.5
    
    // MARK: - State
    
    /// The system-wide accessibility object used to locate the focused app.
    private let systemWideElement: AXUIElement
    
    /// Cache of traversed trees, keyed by window ID + layout hash.
    /// Used to avoid re-traversing windows that haven't changed.
    private var treeCache: [CGWindowID: AXNode] = [:]
    
    /// Logger for this module.
    private let logger = Logger(subsystem: "com.leethack", category: "AccessibilityScanner")
    
    // MARK: - Initialisation
    
    init() {
        // Must be called on the main thread initially in some contexts, but
        // it's generally safe here.
        self.systemWideElement = AXUIElementCreateSystemWide()
    }
    
    // MARK: - API
    
    /// Scans the accessibility tree for the specified window.
    ///
    /// - Parameter window: The window metadata from `WindowDetector`.
    /// - Returns: The root `AXNode` representing the window, or `nil` if it
    ///   cannot be traversed.
    func scan(window: DetectedWindow) async -> AXNode? {
        // Create the application element from the PID
        let appElement = AXUIElementCreateApplication(window.ownerPID)
        
        // Find the specific window element that matches our CGWindowID.
        // AX apps usually have a list of windows.
        var windowsRef: AnyObject?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard error == .success, let axWindows = windowsRef as? [AXUIElement] else {
            return nil
        }
        
        // We match the AX window to the CG window using the title and bounds.
        // Unfortunately, AX doesn't expose the CGWindowID directly.
        var targetWindowElement: AXUIElement?
        
        for axWindow in axWindows {
            if let frame = getFrame(for: axWindow), frame == window.bounds {
                targetWindowElement = axWindow
                break
            }
        }
        
        // Fallback: match by title if bounds don't match exactly
        if targetWindowElement == nil {
            for axWindow in axWindows {
                if let title = getTitle(for: axWindow), title == window.title {
                    targetWindowElement = axWindow
                    break
                }
            }
        }
        
        // If we still can't find it, we might be looking at a window that isn't
        // exposed to AX (e.g. a tool tip or custom overlay).
        guard let windowElement = targetWindowElement else {
            return nil
        }
        
        // Start recursive traversal
        return traverse(element: windowElement, depth: 0)
    }
    
    // MARK: - Traversal
    
    /// Recursively traverses an AXUIElement to build a tree of `AXNode`s.
    private func traverse(element: AXUIElement, depth: Int) -> AXNode? {
        // Stop if we go too deep
        guard depth <= maxDepth else { return nil }
        
        // Extract basic attributes
        let role = getRole(for: element)
        let subrole = getSubrole(for: element)
        let frame = getFrame(for: element)
        
        // If it doesn't have a frame, it's not visible, so we skip it.
        // Exception: the root window element itself might not report a frame reliably.
        if depth > 0 {
            // Ignore tiny elements to reduce visual clutter and processing time
            guard let validFrame = frame, validFrame.width > 20, validFrame.height > 20 else {
                return nil
            }
        }
        
        let title = getTitle(for: element)
        let value = getValue(for: element)
        
        // Map the AX role to our internal SemanticRegionType
        let semanticType = mapRoleToSemanticType(role: role, subrole: subrole)
        
        // Traverse children
        var childNodes: [AXNode] = []
        var childrenRef: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        
        if error == .success, let children = childrenRef as? [AXUIElement] {
            // Limit children to prevent massive trees (e.g. 1000 list items)
            let maxChildren = 20
            for child in children.prefix(maxChildren) {
                if let childNode = traverse(element: child, depth: depth + 1) {
                    childNodes.append(childNode)
                }
            }
        }
        
        return AXNode(
            role: role,
            subrole: subrole,
            semanticType: semanticType,
            title: title,
            value: value,
            frame: frame ?? .zero,
            children: childNodes,
            depth: depth
        )
    }
    
    // MARK: - Attribute Helpers
    
    private func getRole(for element: AXUIElement) -> String {
        var valueRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &valueRef) == .success {
            return valueRef as? String ?? "Unknown"
        }
        return "Unknown"
    }
    
    private func getSubrole(for element: AXUIElement) -> String? {
        var valueRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &valueRef) == .success {
            return valueRef as? String
        }
        return nil
    }
    
    private func getTitle(for element: AXUIElement) -> String? {
        var valueRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &valueRef) == .success {
            let title = valueRef as? String ?? ""
            return title.isEmpty ? nil : title
        }
        return nil
    }
    
    private func getValue(for element: AXUIElement) -> String? {
        var valueRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
            // Value can be many types, we only care if it's text for now
            if let str = valueRef as? String, !str.isEmpty {
                return str
            }
            if let num = valueRef as? NSNumber {
                return num.stringValue
            }
        }
        return nil
    }
    
    private func getFrame(for element: AXUIElement) -> CGRect? {
        // AX exposes position and size separately, or as a CGRect via kAXFrameAttribute.
        // We'll try kAXFrameAttribute first (newer apps), then fallback to position/size.
        
        /* Note: kAXFrameAttribute is technically a private undocumented attribute,
           but it's widely used. To be safe for App Store, we use position and size. */
           
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        
        let posErr = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        let sizeErr = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        
        if posErr == .success && sizeErr == .success {
            var point = CGPoint.zero
            var size = CGSize.zero
            
            // Extract from AXValue
            if let pVal = posRef as! AXValue?, AXValueGetType(pVal) == .cgPoint {
                AXValueGetValue(pVal, .cgPoint, &point)
            } else { return nil }
            
            if let sVal = sizeRef as! AXValue?, AXValueGetType(sVal) == .cgSize {
                AXValueGetValue(sVal, .cgSize, &size)
            } else { return nil }
            
            return CGRect(origin: point, size: size)
        }
        return nil
    }
    
    // MARK: - Role Mapping
    
    /// Maps macOS accessibility roles (like `AXButton`) to our platform-agnostic
    /// `SemanticRegionType`.
    private func mapRoleToSemanticType(role: String, subrole: String?) -> SemanticRegionType {
        // Map specific subroles first
        if let sub = subrole {
            switch sub {
            case "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton":
                return .iconButton
            case "AXToolbarButton":
                return .iconButton
            case "AXTabButton":
                return .tab
            default:
                break
            }
        }
        
        // Map main roles
        switch role {
        case kAXWindowRole: return .window
        case kAXSheetRole: return .sheet
        case kAXDrawerRole: return .panel
            
        case kAXButtonRole: return .button
        case kAXCheckBoxRole: return .checkbox
        case kAXRadioButtonRole: return .button
        case kAXPopUpButtonRole: return .dropdown
        case kAXMenuButtonRole: return .dropdown
        case kAXSliderRole: return .slider
        case kAXTextFieldRole, kAXTextAreaRole: return .textInput
            
        case kAXMenuRole, kAXMenuBarRole: return .menuBar
        case kAXMenuItemRole: return .menuItem
            
        case kAXToolbarRole: return .toolbar
        case kAXSplitGroupRole: return .splitView
        case kAXScrollAreaRole: return .scrollableRegion
        case kAXGroupRole: return .panel // Group usually implies a visual container
            
        case kAXStaticTextRole: return .textBlock
        case kAXImageRole: return .image
        case kAXTableRole, kAXOutlineRole: return .table
        case kAXListRole: return .list
            
        case "AXLink": return .link
            
        default:
            return .unknown
        }
    }
}

// MARK: - AXNode

/// An extracted node from the Accessibility tree.
/// This will be merged with vision results into the final `SemanticNode` tree.
struct AXNode: Sendable {
    let role: String
    let subrole: String?
    let semanticType: SemanticRegionType
    let title: String?
    let value: String?
    let frame: CGRect
    let children: [AXNode]
    let depth: Int
    
    /// Recursively flattens the tree into a list of nodes.
    func flatten() -> [AXNode] {
        var result = [self]
        for child in children {
            result.append(contentsOf: child.flatten())
        }
        return result
    }
}
