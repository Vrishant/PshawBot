// SemanticRegionType.swift
// PshawBot
//
// Enumeration of all semantic regions the system can identify.
// Used across all detectors (AX, Vision, Layout, Heuristic) to classify
// parts of the screen.

import Foundation
import SwiftUI // For Color (though we'll keep UI coupling minimal here)

// MARK: - SemanticRegionType

/// A classification of a specific region on the screen.
///
/// This enum represents the system's semantic understanding of *what* a region is.
/// It merges generic UI elements (buttons, text), OS structures (windows, menus),
/// and domain-specific structures (code editors, terminals).
enum SemanticRegionType: String, CaseIterable, Codable, Sendable {
    
    // MARK: - OS Level / Containers
    
    case window = "Window"
    case menuBar = "Menu Bar"
    case dock = "Dock"
    case floatingWindow = "Floating Window"
    case popup = "Popup / Menu"
    case dialog = "Dialog / Alert"
    case sheet = "Sheet"
    case panel = "Panel"
    case contextMenu = "Context Menu"
    case tooltip = "Tooltip"
    case notification = "Notification"
    
    // MARK: - Layout Structure
    
    case toolbar = "Toolbar"
    case sidebar = "Sidebar"
    case navigationPanel = "Navigation Panel"
    case mainContent = "Main Content"
    case scrollableRegion = "Scrollable Region"
    case statusBar = "Status Bar"
    case tabBar = "Tab Bar"
    case splitView = "Split View Divider"
    
    // MARK: - Content
    
    case textBlock = "Text Block"
    case image = "Image"
    case diagram = "Diagram"
    case pdf = "PDF Content"
    case browserContent = "Web Content"
    case chatArea = "Chat Area"
    case table = "Table"
    case list = "List"
    case form = "Form"
    
    // MARK: - Interactive Elements
    
    case button = "Button"
    case iconButton = "Icon Button"
    case textInput = "Text Input"
    case searchBar = "Search Bar"
    case addressBar = "Address Bar"
    case checkbox = "Checkbox"
    case toggle = "Toggle / Switch"
    case slider = "Slider"
    case dropdown = "Dropdown"
    case link = "Link"
    case tab = "Tab"
    case menuItem = "Menu Item"
    case disclosureTriangle = "Disclosure Triangle"
    
    // MARK: - Developer Specific
    
    case editor = "Code Editor"
    case activeFile = "Active File Content"
    case lineGutter = "Line Numbers"
    case minimap = "Minimap"
    case terminal = "Terminal"
    case integratedTerminal = "Integrated Terminal"
    case debugger = "Debugger"
    case problemsPanel = "Problems Panel"
    case fileExplorer = "File Explorer"
    case gitPanel = "Source Control"
    case editorTabs = "Editor Tabs"
    case console = "Console"
    case outputWindow = "Output Log"
    case searchPanel = "Global Search"
    case extensionsPanel = "Extensions"
    case settingsEditor = "Settings"
    case diffView = "Diff View"
    case mergeConflict = "Merge Conflict"
    case breakpointGutter = "Breakpoint Margin"
    case callStack = "Call Stack"
    case variables = "Variables"
    case watchExpressions = "Watch Expressions"
    
    // MARK: - Fallbacks
    
    case unknown = "Unknown Region"
    
    // MARK: - Properties
    
    /// The SF Symbol icon name representing this region type.
    var iconName: String {
        switch self {
        case .window: return "macwindow"
        case .menuBar: return "menubar.rectangle"
        case .dock: return "dock.rectangle"
        case .floatingWindow: return "uiwindow.split.2x1"
        case .popup, .contextMenu: return "contextualmenu.and.cursorarrow"
        case .dialog, .sheet: return "macwindow.badge.exclamationmark"
        case .panel: return "macwindow.and.cursorarrow"
        case .tooltip, .notification: return "bubble.left.fill"
            
        case .toolbar: return "toolbar"
        case .sidebar: return "sidebar.left"
        case .navigationPanel: return "list.bullet.indent"
        case .mainContent: return "rectangle.fill"
        case .scrollableRegion: return "scroll.fill"
        case .statusBar: return "capsule.bottom"
        case .tabBar: return "uiwindow.split.2x1"
        case .splitView: return "divider.vertical"
            
        case .textBlock: return "text.alignleft"
        case .image: return "photo"
        case .diagram: return "chart.bar.doc.text"
        case .pdf: return "doc.richtext"
        case .browserContent: return "safari"
        case .chatArea: return "message"
        case .table: return "tablecells"
        case .list: return "list.bullet"
        case .form: return "list.clipboard"
            
        case .button: return "button.horizontal"
        case .iconButton: return "plus.circle"
        case .textInput: return "character.cursor.ibeam"
        case .searchBar: return "magnifyingglass"
        case .addressBar: return "globe"
        case .checkbox: return "checkmark.square"
        case .toggle: return "switch.2"
        case .slider: return "slider.horizontal.3"
        case .dropdown: return "chevron.up.chevron.down"
        case .link: return "link"
        case .tab: return "folder"
        case .menuItem: return "filemenu.and.cursorarrow"
        case .disclosureTriangle: return "chevron.right"
            
        case .editor, .activeFile: return "curlybraces"
        case .lineGutter: return "list.number"
        case .minimap: return "map"
        case .terminal, .integratedTerminal: return "terminal"
        case .debugger: return "ladybug"
        case .problemsPanel: return "exclamationmark.triangle"
        case .fileExplorer: return "folder.tree"
        case .gitPanel: return "arrow.triangle.branch"
        case .editorTabs: return "doc.on.doc"
        case .console, .outputWindow: return "apple.terminal"
        case .searchPanel: return "doc.text.magnifyingglass"
        case .extensionsPanel: return "puzzlepiece"
        case .settingsEditor: return "gearshape"
        case .diffView: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .mergeConflict: return "exclamationmark.arrow.triangle.2.circlepath"
        case .breakpointGutter: return "circle.fill"
        case .callStack: return "list.bullet.rectangle.portrait"
        case .variables: return "v.square"
        case .watchExpressions: return "eye"
            
        case .unknown: return "questionmark.dashed"
        }
    }
    
    /// True if this element is typically interactive (clickable/typable).
    var isInteractive: Bool {
        switch self {
        case .button, .iconButton, .textInput, .searchBar, .addressBar,
             .checkbox, .toggle, .slider, .dropdown, .link, .tab, .menuItem,
             .disclosureTriangle, .editor, .terminal, .integratedTerminal:
            return true
        default:
            return false
        }
    }
    
    /// True if this element primarily serves as a container for other elements.
    var isContainer: Bool {
        switch self {
        case .window, .menuBar, .dock, .floatingWindow, .popup, .dialog, .sheet,
             .panel, .contextMenu, .toolbar, .sidebar, .navigationPanel,
             .mainContent, .scrollableRegion, .tabBar, .browserContent,
             .chatArea, .table, .list, .form, .fileExplorer, .gitPanel,
             .extensionsPanel, .settingsEditor:
            return true
        default:
            return false
        }
    }
    
    /// Returns the category for colouring in the UI.
    var uiCategory: RegionCategory {
        if isInteractive {
            return .interactive
        } else if self == .window || self == .menuBar || self == .dock {
            return .osLevel
        } else if isContainer {
            return .container
        } else if self == .textBlock || self == .image || self == .diagram || self == .pdf || self == .editor || self == .terminal {
            return .content
        } else {
            return .structural
        }
    }
}

// MARK: - RegionCategory

enum RegionCategory {
    case osLevel
    case container
    case content
    case interactive
    case structural
    
    /// Base colour mapping for the UI overlay.
    var color: Color {
        switch self {
        case .osLevel: return .blue
        case .container: return .indigo
        case .content: return .orange
        case .interactive: return .green
        case .structural: return .gray
        }
    }
}
