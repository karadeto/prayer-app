//
//  PrayerProApp.swift
//  PrayerPro
//
//  Created by Ali Karadeniz on 24.07.25.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct PrayerProApp: App {
    let persistenceController = PersistenceController.shared
    
    // Status bar widget controller
    @StateObject private var statusBarController = StatusBarController.shared
    
    // Preferences manager
    @StateObject private var preferencesManager = PreferencesManager.shared
    
    // Data persistence service
    @StateObject private var dataPersistenceService = DataPersistenceService.shared
    
    // Session manager
    @StateObject private var sessionManager = SessionManager.shared
    
    // Error handling service
    @StateObject private var errorHandlingService = ErrorHandlingService.shared
    
    // App delegate for lifecycle management
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PrayerPro", category: "App")
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .modelContainer(persistenceController.modelContainer)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    configureWindow()
                    setupNetworkMonitoring()
                    
                    // Setup data persistence first before other services
                    setupDataPersistence()
                    
                    // Add delay before setting up other services that depend on SwiftData
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        setupStatusBarWidget()
                        setupNotificationSystem()
                        setupiCloudSync()
                    }
                }
                .environmentObject(statusBarController)
                .environmentObject(preferencesManager)
                .environmentObject(dataPersistenceService)
                .environmentObject(sessionManager)
                .environmentObject(errorHandlingService)
                .withErrorHandling()
                .onReceive(NotificationCenter.default.publisher(for: .refreshAllData)) { _ in
                    refreshAllData()
                }
                .onReceive(NotificationCenter.default.publisher(for: .resetAppData)) { _ in
                    resetAppData()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 650)
        .windowResizability(.contentSize)
        
        // Native SwiftUI Settings window
        Settings {
            PreferencesView()
                .modelContainer(persistenceController.modelContainer)
                .environmentObject(preferencesManager)
                .environmentObject(statusBarController)
        }
        
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
                
                Divider()
                
                Button("Toggle Status Bar Widget") {
                    preferencesManager.isStatusBarWidgetEnabled.toggle()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
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
            
            // Set window identifier for status bar controller
            window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
            
            // Restore window frame from session if available
            if let savedFrame = sessionManager.windowFrame {
                window.setFrame(savedFrame, display: true)
            }
            
            // Listen for window frame changes to save to session
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { _ in
                self.sessionManager.updateWindowFrame(window.frame)
            }
            
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { _ in
                self.sessionManager.updateWindowFrame(window.frame)
            }
        }
    }
    
    private func setupNetworkMonitoring() {
        // Initialize network monitoring early
        let _ = NetworkOptimizer.shared
        logger.info("✅ Network monitoring initialized")
        
        // Give it a moment to detect network status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.errorHandlingService.updateSystemAvailability()
        }
    }
    
    private func setupDataPersistence() {
        // Initialize data persistence service
        Task {
            do {
                await dataPersistenceService.initialize(with: persistenceController.modelContainer.mainContext)
                
                // Check session info and handle accordingly
                let sessionInfo = dataPersistenceService.getSessionInfo()
                
                if sessionInfo.isFresh {
                    logger.info("🆕 Fresh app launch - showing welcome experience")
                    // Could show onboarding or welcome screen
                } else if sessionInfo.hasVersionChanged {
                    logger.info("🔄 App version changed - checking for migration")
                    // Migration was already handled in initialize
                } else if sessionInfo.isStale {
                    logger.info("⏰ Session is stale - refreshing data")
                    // Could trigger data refresh
                }
                
                // Restore last selected location
                if let lastLocation = await dataPersistenceService.restoreLastSelectedLocation() {
                    logger.info("📍 Restored last selected location: \(lastLocation.name)")
                    // Notify UI components about restored location
                    NotificationCenter.default.post(
                        name: Notification.Name("LocationSelected"),
                        object: lastLocation,
                        userInfo: nil
                    )
                }
                
                logger.info("✅ Data persistence setup completed")
            } catch {
                errorHandlingService.handleError(error, context: "setupDataPersistence", showToUser: true)
            }
        }
    }
    
    private func setupStatusBarWidget() {
        do {
            // Configure status bar widget with model context
            statusBarController.configure(with: persistenceController.modelContainer.mainContext)
            
            // Set initial visibility based on preferences
            statusBarController.isVisible = preferencesManager.isStatusBarWidgetEnabled
            
            // Listen for location changes to update status bar
            NotificationCenter.default.addObserver(
                forName: Notification.Name("LocationSelected"),
                object: nil,
                queue: .main
            ) { notification in
                if let location = notification.object as? Location {
                    statusBarController.updateLocation(location)
                }
            }
            
            logger.info("✅ Status bar widget setup completed")
        } catch {
            errorHandlingService.handleError(error, context: "setupStatusBarWidget", showToUser: false)
        }
    }
    
    private func setupNotificationSystem() {
        // Initialize notification system
        let notificationManager = NotificationManager.shared
        let notificationScheduler = NotificationScheduler.shared
        
        // Request notification permission on first launch
        Task { @MainActor in
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
            forName: Notification.Name("NotificationPreferencesChanged"),
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await notificationManager.rescheduleAllNotifications()
            }
        }
        
        // Listen for prayer times requests from notification system
        NotificationCenter.default.addObserver(
            forName: Notification.Name("RequestPrayerTimesForNotifications"),
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
            // Add delay to ensure SwiftData is fully initialized
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            do {
                print("🔄 Initializing iCloud sync...")
                
                // Check iCloud availability first
                try await iCloudSyncService.shared.verifyiCloudAvailability()
                
                // Verify CloudKit schema
                try await CloudKitSchemaHelper.verifySchema()
                
                // Ensure we're on main actor for SwiftData access
                await MainActor.run {
                    Task {
                        do {
                            print("🚀 Starting iCloud sync data operations...")
                            
                            // Perform initial sync from iCloud
                            print("📥 Syncing completions from iCloud...")
                            try await iCloudSyncService.shared.syncCompletionsFromiCloud(in: persistenceController.modelContainer.mainContext)
                            
                            // Sync any unsynced local completions
                            print("📤 Syncing unsynced local completions...")
                            try await PrayerCompletionManager.shared.syncUnsyncedCompletions(in: persistenceController.modelContainer.mainContext)
                            
                            // Restore completion states for all prayers after sync
                            print("🔄 Restoring completion states...")
                            try await PrayerCompletionManager.shared.restoreAllCompletionStates(in: persistenceController.modelContainer.mainContext)
                            
                            print("✅ iCloud sync data operations completed successfully")
                            
                            // Notify other parts of the app that sync is complete
                            NotificationCenter.default.post(
                                name: Notification.Name("iCloudSyncCompleted"),
                                object: nil
                            )
                        } catch {
                            print("⚠️ iCloud sync data operations failed: \(error)")
                        }
                    }
                }
                
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
                
                // Still try to restore completion states from local data
                await MainActor.run {
                    Task {
                        do {
                            try await PrayerCompletionManager.shared.restoreAllCompletionStates(in: persistenceController.modelContainer.mainContext)
                        } catch {
                            print("⚠️ Failed to restore completion states from local data: \(error)")
                        }
                    }
                }
                
            } catch {
                print("⚠️ iCloud sync initialization failed: \(error.localizedDescription)")
                print("📱 App will continue to function with local data only")
                
                // Still try to restore completion states from local data
                await MainActor.run {
                    Task {
                        do {
                            try await PrayerCompletionManager.shared.restoreAllCompletionStates(in: persistenceController.modelContainer.mainContext)
                        } catch {
                            print("⚠️ Failed to restore completion states from local data: \(error)")
                        }
                    }
                }
            }
        }
        
        // Set up periodic sync (only if iCloud is available)
        setupPeriodicSync()
        
        // Set up periodic cleanup
        setupPeriodicCleanup()
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
    
    // Settings window is now handled natively by SwiftUI Settings scene
    
    private func setupPeriodicCleanup() {
        // Perform cleanup every 24 hours
        Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task {
                do {
                    try await self.dataPersistenceService.performCleanup()
                    print("✅ Periodic cleanup completed successfully")
                } catch {
                    print("⚠️ Periodic cleanup failed: \(error)")
                }
            }
        }
        
        // Perform cleanup when app becomes active (if it's been more than 24 hours)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                do {
                    let healthReport = try await self.dataPersistenceService.getSystemHealthReport()
                    
                    // Perform cleanup if needed
                    if healthReport.needsMaintenance {
                        print("🧹 System needs maintenance, performing cleanup...")
                        try await self.dataPersistenceService.performCleanup()
                        print("✅ Maintenance cleanup completed")
                    }
                } catch {
                    print("⚠️ Health check or cleanup failed: \(error)")
                }
            }
        }
    }
    
    private func refreshAllData() {
        logger.info("🔄 Refreshing all app data")
        
        Task {
            do {
                // Clear caches
                await CacheManager.shared.performMemoryCleanup()
                
                // Update system availability
                errorHandlingService.updateSystemAvailability()
                
                // Refresh current location and prayer times if available
                NotificationCenter.default.post(name: .refreshPrayerTimes, object: nil)
                
                logger.info("✅ Data refresh completed")
            } catch {
                errorHandlingService.handleError(error, context: "refreshAllData", showToUser: true)
            }
        }
    }
    
    private func resetAppData() {
        logger.warning("⚠️ Resetting all app data")
        
        Task {
            do {
                // Clear all caches
                await CacheManager.shared.performMemoryCleanup()
                
                // Clear user defaults
                let domain = Bundle.main.bundleIdentifier!
                UserDefaults.standard.removePersistentDomain(forName: domain)
                UserDefaults.standard.synchronize()
                
                // Clear error logs
                errorHandlingService.clearErrorLog()
                
                // Reset preferences
                preferencesManager.resetAllPreferences()
                
                logger.info("✅ App data reset completed")
                
                // Show success message
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let alert = NSAlert()
                    alert.messageText = "Data Reset Complete"
                    alert.informativeText = "All app data has been reset. Please restart the app to apply changes."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                
            } catch {
                errorHandlingService.handleError(error, context: "resetAppData", showToUser: true)
            }
        }
    }
}
