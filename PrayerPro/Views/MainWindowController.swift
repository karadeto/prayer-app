//
//  MainWindowController.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import AppKit

class MainWindowController: NSWindowController {
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.init(window: window)
        
        setupWindow()
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        // Window configuration
        window.title = "Prayer Times"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        
        // Set minimum size
        window.minSize = NSSize(width: 700, height: 500)
        
        // Center window
        window.center()
        
        // Set up toolbar
        setupToolbar()
        
        // Configure window appearance
        configureWindowAppearance()
    }
    
    private func setupToolbar() {
        guard let window = window else { return }
        
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.delegate = self
        
        window.toolbar = toolbar
    }
    
    private func configureWindowAppearance() {
        guard let window = window else { return }
        
        // Set window background
        window.backgroundColor = NSColor.windowBackgroundColor
        
        // Configure for modern macOS appearance
        if #available(macOS 11.0, *) {
            window.subtitle = ""
        }
        
        // Set up window restoration
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        
        // Additional setup after window loads
        setupWindowObservers()
    }
    
    private func setupWindowObservers() {
        guard let window = window else { return }
        
        // Observe window state changes
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: window,
            queue: .main
        ) { _ in
            // Handle window becoming main
            self.handleWindowBecameMain()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignMainNotification,
            object: window,
            queue: .main
        ) { _ in
            // Handle window resigning main
            self.handleWindowResignedMain()
        }
    }
    
    private func handleWindowBecameMain() {
        // Refresh data when window becomes active
        NotificationCenter.default.post(name: .refreshPrayerTimes, object: nil)
    }
    
    private func handleWindowResignedMain() {
        // Handle window becoming inactive if needed
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Toolbar Delegate

extension MainWindowController: NSToolbarDelegate {
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        switch itemIdentifier {
        case .sidebarToggle:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Toggle Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Show or hide the sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Sidebar")
            item.target = self
            item.action = #selector(toggleSidebar)
            return item
            
        case .refresh:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Refresh"
            item.paletteLabel = "Refresh"
            item.toolTip = "Refresh prayer times"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            item.target = self
            item.action = #selector(refreshPrayerTimes)
            return item
            
        default:
            return nil
        }
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .sidebarToggle,
            .flexibleSpace,
            .refresh
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .sidebarToggle,
            .refresh,
            .flexibleSpace,
            .space
        ]
    }
    
    @objc private func toggleSidebar() {
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }
    
    @objc private func refreshPrayerTimes() {
        NotificationCenter.default.post(name: .refreshPrayerTimes, object: nil)
    }
}

// MARK: - Toolbar Item Identifiers

extension NSToolbarItem.Identifier {
    static let sidebarToggle = NSToolbarItem.Identifier("SidebarToggle")
    static let refresh = NSToolbarItem.Identifier("Refresh")
}

// MARK: - Notification Names (defined in Extensions.swift)

// MARK: - Window Style Configuration

extension MainWindowController {
    
    func configureForWeatherAppStyle() {
        guard let window = window else { return }
        
        // Configure window to match Apple Weather app style
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // Set up unified toolbar style
        if let toolbar = window.toolbar {
            toolbar.displayMode = .iconOnly
        }
        
        // Configure background
        window.backgroundColor = NSColor.windowBackgroundColor
        
        // Set up window level and collection behavior
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
    }
    
    func setWindowFrame(width: CGFloat, height: CGFloat) {
        guard let window = window else { return }
        
        let currentFrame = window.frame
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y,
            width: width,
            height: height
        )
        
        window.setFrame(newFrame, display: true, animate: true)
    }
}