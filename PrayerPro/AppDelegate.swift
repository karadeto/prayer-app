//
//  AppDelegate.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        // Don't quit when main window is closed - keep status bar widget active
        return false
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure app to run in background
        NSApp.setActivationPolicy(.regular)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Show main window when app icon is clicked in dock
        if !flag {
            for window in sender.windows {
                if window.identifier?.rawValue == "MainWindow" {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    break
                }
            }
        }
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up status bar widget
        StatusBarController.shared.hideWidget()
    }
}