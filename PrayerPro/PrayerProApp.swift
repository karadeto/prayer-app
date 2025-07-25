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
    
    // Status bar widget controller
    @StateObject private var statusBarController = StatusBarController.shared
    
    // Preferences manager
    @StateObject private var preferencesManager = PreferencesManager.shared
    
    // App delegate for lifecycle management
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .modelContainer(persistenceController.modelContainer)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    configureWindow()
                    setupStatusBarWidget()
                    setupNotificationSystem()
                    setupiCloudSync()
                }
                .environmentObject(statusBarController)
                .environmentObject(preferencesManager)
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
            
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    showPreferences()
                }
                .keyboardShortcut(",", modifiers: .command)
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
                
                Divider()
                
                Button("Toggle Status Bar Widget") {
                    preferencesManager.isStatusBarWidgetEnabled.toggle()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
        .windowResizability(.contentSize)
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
            
            // Set window identifier for status bar controller
            window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
        }
    }
    
    private func setupStatusBarWidget() {
        // Configure status bar widget with model context
        statusBarController.configure(with: persistenceController.modelContainer.mainContext)
        
        // Set initial visibility based on preferences
        statusBarController.isVisible = preferencesManager.isStatusBarWidgetEnabled
        
        // Listen for location changes to update status bar
        NotificationCenter.default.addObserver(
            forName: .locationSelected,
            object: nil,
            queue: .main
        ) { notification in
            if let location = notification.object as? Location {
                statusBarController.updateLocation(location)
            }
        }
    }
    
    private func setupNotificationSystem() {
        // Initialize notification system
        let notificationManager = NotificationManager.shared
        let notificationScheduler = NotificationScheduler.shared
        
        // Request notification permission on first launch
        Task {
            await notificationManager.updatePermissionStatus()
            
            // If notifications are enabled but permission not granted, request it
            if preferencesManager.notificationsEnabled && !notificationManager.isPermissionGranted {
                let granted = await notificationManager.requestNotificationPermission()
                if granted {
                    await notificationManager.scheduleAllNotifications()
                }
            } else if notificationManager.isPermissionGranted {
                // Schedule notifications if permission already granted
                await notificationManager.scheduleAllNotifications()
            }
        }
        
        // Listen for preference changes to update notifications
        NotificationCenter.default.addObserver(
            forName: .notificationPreferencesChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await notificationManager.rescheduleAllNotifications()
            }
        }
        
        // Listen for prayer times requests from notification system
        NotificationCenter.default.addObserver(
            forName: .requestPrayerTimesForNotifications,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await self.handleNotificationPrayerTimesRequest()
            }
        }
    }
    
    private func handleNotificationPrayerTimesRequest() async {
        let notificationManager = NotificationManager.shared
        let locationService = LocationService.shared
        let prayerTimeService = PrayerTimeService.shared
        let context = persistenceController.modelContainer.mainContext
        
        do {
            // Get the location to use for notifications
            var location: Location?
            
            if preferencesManager.useGPSForNotifications {
                // Use GPS location
                location = try await locationService.getCurrentLocation()
            } else if let locationId = preferencesManager.notificationLocationId {
                // Use specific location - we'd need to fetch from context
                // For now, we'll use GPS as fallback
                location = try await locationService.getCurrentLocation()
            }
            
            guard let notificationLocation = location else {
                print("No location available for notifications")
                return
            }
            
            // Get prayer times for the location
            let prayers = try await prayerTimeService.getPrayerTimes(for: notificationLocation, in: context)
            
            // Schedule notifications with the prayer times
            await notificationManager.scheduleNotifications(prayers: prayers, location: notificationLocation)
            
        } catch {
            print("Failed to get prayer times for notifications: \(error)")
        }
    }
    
    private func setupiCloudSync() {
        // Initialize iCloud sync service with proper error handling
        Task {
            do {
                print("🔄 Initializing iCloud sync...")
                
                // Check iCloud availability first
                try await iCloudSyncService.shared.verifyiCloudAvailability()
                
                // Verify CloudKit schema
                try await CloudKitSchemaHelper.verifySchema()
                
                // Perform initial sync from iCloud
                try await iCloudSyncService.shared.syncCompletionsFromiCloud(in: persistenceController.modelContainer.mainContext)
                
                // Sync any unsynced local completions
                try await PrayerCompletionManager.shared.syncUnsyncedCompletions(in: persistenceController.modelContainer.mainContext)
                
                print("✅ iCloud sync initialized successfully")
                
            } catch let error as iCloudSyncError {
                switch error {
                case .noiCloudAccount:
                    print("ℹ️ No iCloud account configured - sync disabled")
                case .containerNotConfigured:
                    print("⚠️ CloudKit container not configured in Apple Developer portal")
                    print("📋 Please ensure the CloudKit container 'iCloud.com.karadeniz.prayerpro.PrayerPro' is properly configured")
                case .schemaNotConfigured:
                    print("⚠️ CloudKit schema not configured")
                    CloudKitSchemaHelper.printSchemaInstructions()
                case .networkUnavailable:
                    print("⚠️ Network unavailable - iCloud sync will retry later")
                case .iCloudRestricted:
                    print("⚠️ iCloud access is restricted on this device")
                case .iCloudTemporarilyUnavailable:
                    print("⚠️ iCloud is temporarily unavailable - will retry later")
                default:
                    print("⚠️ iCloud sync initialization failed: \(error.localizedDescription)")
                }
                
                // Continue without iCloud sync - app should still function
                print("📱 App will continue to function with local data only")
                
            } catch {
                print("⚠️ iCloud sync initialization failed: \(error.localizedDescription)")
                print("📱 App will continue to function with local data only")
            }
        }
        
        // Set up periodic sync (only if iCloud is available)
        setupPeriodicSync()
    }
    
    private func setupPeriodicSync() {
        // Sync every 5 minutes when app is active
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task {
                do {
                    // Only attempt sync if iCloud is available
                    try await iCloudSyncService.shared.verifyiCloudAvailability()
                    try await PrayerCompletionManager.shared.syncUnsyncedCompletions(
                        in: self.persistenceController.modelContainer.mainContext
                    )
                } catch let error as iCloudSyncError {
                    // Silently handle expected iCloud errors during periodic sync
                    switch error {
                    case .noiCloudAccount, .containerNotConfigured, .schemaNotConfigured:
                        // These are configuration issues, don't spam logs
                        break
                    case .networkUnavailable:
                        // Network issues are temporary, don't spam logs
                        break
                    default:
                        print("Periodic sync failed: \(error.localizedDescription)")
                    }
                } catch {
                    print("Periodic sync failed: \(error.localizedDescription)")
                }
            }
        }
        
        // Listen for app becoming active to trigger sync
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                do {
                    // Only attempt sync if iCloud is available
                    try await iCloudSyncService.shared.verifyiCloudAvailability()
                    try await PrayerCompletionManager.shared.performFullSyncFromiCloud(
                        in: self.persistenceController.modelContainer.mainContext
                    )
                } catch let error as iCloudSyncError {
                    // Silently handle expected iCloud errors during app activation
                    switch error {
                    case .noiCloudAccount, .containerNotConfigured, .schemaNotConfigured:
                        // These are configuration issues, don't spam logs
                        break
                    default:
                        print("App activation sync failed: \(error.localizedDescription)")
                    }
                } catch {
                    print("App activation sync failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showPreferences() {
        let preferencesView = PreferencesView()
        let hostingController = NSHostingController(rootView: preferencesView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.title = "Preferences"
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }
}
