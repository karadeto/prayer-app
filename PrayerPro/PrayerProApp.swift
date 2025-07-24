//
//  PrayerProApp.swift
//  PrayerPro
//
//  Created by Ali Karadeniz on 24.07.25.
//

import SwiftUI
import SwiftData

@main
struct PrayerProApp: App {
    let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .modelContainer(persistenceController.modelContainer)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    configureWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 650)
        .commands {
            // Add custom menu commands
            CommandGroup(replacing: .newItem) {
                Button("New Location Search") {
                    // This will be handled by the UI
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil, userInfo: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                
                Button("Refresh Prayer Times") {
                    NotificationCenter.default.post(name: .refreshPrayerTimes, object: nil, userInfo: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
    
    private func configureWindow() {
        // Configure the main window appearance
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor.windowBackgroundColor
            
            // Set minimum size
            window.minSize = NSSize(width: 700, height: 500)
            
            // Configure for modern macOS appearance
            if #available(macOS 11.0, *) {
                window.subtitle = ""
            }
        }
    }
}
