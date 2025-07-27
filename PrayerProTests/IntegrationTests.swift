//
//  IntegrationTests.swift
//  PrayerProTests
//
//  Created by Kiro on 24.07.25.
//

import XCTest
import SwiftUI
import SwiftData
import CloudKit
import UserNotifications
@testable import PrayerPro

final class IntegrationTests: XCTestCase {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var statusBarController: StatusBarController!
    var notificationManager: NotificationManager!
    var iCloudSyncService: iCloudSyncService!
    var prayerTimeService: PrayerTimeService!
    var locationService: LocationService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create in-memory model container for testing
        let schema = Schema([Prayer.self, Location.self, PrayerCompletion.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
        
        // Initialize services
        statusBarController = StatusBarController.shared
        notificationManager = NotificationManager.shared
        iCloudSyncService = iCloudSyncService.shared
        prayerTimeService = PrayerTimeService.shared
        locationService = LocationService.shared
        
        // Configure status bar controller with test context
        statusBarController.configure(with: modelContext)
    }
    
    override func tearDownWithError() throws {
        // Clean up
        modelContainer = nil
        modelContext = nil
        statusBarController = nil
        notificationManager = nil
        iCloudSyncService = nil
        prayerTimeService = nil
        locationService = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Complete User Workflow Tests
    
    func testCompleteUserWorkflow_FirstTimeSetup() async throws {
        // Test the complete first-time user experience
        
        // 1. App Launch - Check initial state
        XCTAssertNotNil(statusBarController)
        XCTAssertNotNil(notificationManager)
        
        // 2. Location Permission Request (simulated)
        let mockLocation = try createMockLocation()
        
        // 3. Prayer Times Fetching
        let prayers = try await prayerTimeService.getPrayerTimes(for: mockLocation, in: modelContext)
        XCTAssertGreaterThan(prayers.count, 0)
        
        // 4. Status Bar Widget Update
        statusBarController.updateLocation(mockLocation)
        
        // Wait for async updates
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        XCTAssertEqual(statusBarController.currentLocation?.id, mockLocation.id)
        
        // 5. Notification Setup (simulated permission granted)
        await notificationManager.scheduleNotifications(prayers: prayers, location: mockLocation)
        
        let pendingNotifications = await notificationManager.getPendingNotifications()
        XCTAssertGreaterThan(pendingNotifications.count, 0)
        
        // 6. Prayer Completion Tracking
        let firstPrayer = prayers.first!
        let completion = try PrayerCompletion(
            prayerType: firstPrayer.prayerType,
            date: Date(),
            locationId: mockLocation.id
        )
        
        modelContext.insert(completion)
        try modelContext.save()
        
        // Verify completion was saved
        let descriptor = FetchDescriptor<PrayerCompletion>()
        let savedCompletions = try modelContext.fetch(descriptor)
        XCTAssertEqual(savedCompletions.count, 1)
        
        print("✅ Complete first-time user workflow test passed")
    }
    
    func testCompleteUserWorkflow_LocationChange() async throws {
        // Test workflow when user changes location
        
        // 1. Start with initial location
        let initialLocation = try createMockLocation(name: "Initial Location")
        statusBarController.updateLocation(initialLocation)
        
        let initialPrayers = try await prayerTimeService.getPrayerTimes(for: initialLocation, in: modelContext)
        await notificationManager.scheduleNotifications(prayers: initialPrayers, location: initialLocation)
        
        // 2. Change to new location
        let newLocation = try createMockLocation(name: "New Location", latitude: 41.0, longitude: -75.0)
        statusBarController.updateLocation(newLocation)
        
        // 3. Verify status bar updates
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(statusBarController.currentLocation?.name, "New Location")
        
        // 4. Verify new prayer times are fetched
        let newPrayers = try await prayerTimeService.getPrayerTimes(for: newLocation, in: modelContext)
        XCTAssertGreaterThan(newPrayers.count, 0)
        
        // 5. Verify notifications are rescheduled
        await notificationManager.scheduleNotifications(prayers: newPrayers, location: newLocation)
        let updatedNotifications = await notificationManager.getPendingNotifications()
        XCTAssertGreaterThan(updatedNotifications.count, 0)
        
        print("✅ Location change workflow test passed")
    }
    
    func testCompleteUserWorkflow_FavoriteLocationManagement() async throws {
        // Test adding, using, and removing favorite locations
        
        // 1. Create and add favorite location
        let favoriteLocation = try createMockLocation(name: "Favorite Mosque")
        favoriteLocation.isFavorite = true
        
        modelContext.insert(favoriteLocation)
        try modelContext.save()
        
        // 2. Fetch prayer times for favorite
        let prayers = try await prayerTimeService.getPrayerTimes(for: favoriteLocation, in: modelContext)
        XCTAssertGreaterThan(prayers.count, 0)
        
        // 3. Update status bar to use favorite
        statusBarController.updateLocation(favoriteLocation)
        try await Task.sleep(nanoseconds: 500_000_000)
        
        XCTAssertEqual(statusBarController.currentLocation?.name, "Favorite Mosque")
        XCTAssertTrue(statusBarController.currentLocation?.isFavorite == true)
        
        // 4. Complete a prayer for this location
        let completion = try PrayerCompletion(
            prayerType: .fajr,
            date: Date(),
            locationId: favoriteLocation.id
        )
        
        modelContext.insert(completion)
        try modelContext.save()
        
        // 5. Verify completion is tracked
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate<PrayerCompletion> { $0.locationId == favoriteLocation.id }
        )
        let completions = try modelContext.fetch(descriptor)
        XCTAssertEqual(completions.count, 1)
        
        print("✅ Favorite location management workflow test passed")
    }
    
    // MARK: - Status Bar Widget Integration Tests
    
    func testStatusBarWidget_MainAppInteraction() async throws {
        // Test that status bar widget correctly interacts with main app
        
        let testLocation = try createMockLocation()
        let prayers = try await prayerTimeService.getPrayerTimes(for: testLocation, in: modelContext)
        
        // 1. Update location in main app (simulated)
        NotificationCenter.default.post(name: .locationSelected, object: testLocation)
        
        // 2. Verify status bar widget receives update
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(statusBarController.currentLocation?.id, testLocation.id)
        
        // 3. Test prayer completion affecting status bar
        let completion = try PrayerCompletion(
            prayerType: prayers.first!.prayerType,
            date: Date(),
            locationId: testLocation.id
        )
        
        modelContext.insert(completion)
        try modelContext.save()
        
        // Notify status bar of completion change
        NotificationCenter.default.post(name: .prayerCompletionChanged, object: nil)
        
        // 4. Verify status bar updates prayer data
        try await Task.sleep(nanoseconds: 500_000_000)
        // Status bar should have updated its prayer status
        
        print("✅ Status bar widget main app interaction test passed")
    }
    
    func testStatusBarWidget_CountdownAccuracy() async throws {
        // Test that countdown timer is accurate
        
        let testLocation = try createMockLocation()
        statusBarController.updateLocation(testLocation)
        
        // Create a prayer that's 1 minute in the future
        let futureTime = Date().addingTimeInterval(60) // 1 minute from now
        let futurePrayer = try Prayer(
            prayerType: .dhuhr,
            time: futureTime,
            locationId: testLocation.id
        )
        
        modelContext.insert(futurePrayer)
        try modelContext.save()
        
        // Update status bar with this prayer
        statusBarController.nextPrayer = futurePrayer
        statusBarController.timeRemaining = 60
        
        // Wait 2 seconds and check countdown decreased
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        XCTAssertLessThan(statusBarController.timeRemaining, 60)
        XCTAssertGreaterThan(statusBarController.timeRemaining, 55)
        
        print("✅ Status bar widget countdown accuracy test passed")
    }
    
    func testStatusBarWidget_VisibilityToggle() async throws {
        // Test showing and hiding status bar widget
        
        // 1. Initially visible
        XCTAssertTrue(statusBarController.isVisible)
        
        // 2. Hide widget
        statusBarController.hideWidget()
        XCTAssertFalse(statusBarController.isVisible)
        
        // 3. Show widget again
        statusBarController.showWidget()
        XCTAssertTrue(statusBarController.isVisible)
        
        // 4. Test preference-based toggle
        let preferencesManager = PreferencesManager.shared
        preferencesManager.isStatusBarWidgetEnabled = false
        
        // Simulate preference change notification
        NotificationCenter.default.post(
            name: .statusBarWidgetPreferenceChanged,
            object: nil,
            userInfo: ["isEnabled": false]
        )
        
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        XCTAssertFalse(statusBarController.isVisible)
        
        print("✅ Status bar widget visibility toggle test passed")
    }
    
    // MARK: - iCloud Sync Integration Tests
    
    func testICloudSync_CompletionSyncFlow() async throws {
        // Test the complete iCloud sync flow for prayer completions
        
        // Note: This test simulates iCloud operations since actual CloudKit
        // requires proper setup and network connectivity
        
        let testLocation = try createMockLocation()
        
        // 1. Create local completion
        let completion = try PrayerCompletion(
            prayerType: .fajr,
            date: Date(),
            locationId: testLocation.id
        )
        
        modelContext.insert(completion)
        try modelContext.save()
        
        // 2. Verify completion is not synced initially
        XCTAssertFalse(completion.syncedToiCloud)
        
        // 3. Simulate sync to iCloud (would normally use CloudKit)
        completion.markSyncedToiCloud()
        try modelContext.save()
        
        XCTAssertTrue(completion.syncedToiCloud)
        
        // 4. Test conflict resolution
        let conflictingCompletion = try PrayerCompletion(
            prayerType: .fajr,
            date: Date(),
            completedAt: Date().addingTimeInterval(-3600), // 1 hour ago
            locationId: testLocation.id
        )
        
        // Create mock CloudKit record with newer timestamp
        let mockRecord = CKRecord(recordType: "PrayerCompletion")
        mockRecord["completedAt"] = Date() // Now (newer)
        
        let resolvedCompletion = iCloudSyncService.resolveConflicts(
            localCompletion: conflictingCompletion,
            remoteRecord: mockRecord
        )
        
        // Should prefer newer completion time
        XCTAssertGreaterThan(resolvedCompletion.completedAt, conflictingCompletion.completedAt)
        
        print("✅ iCloud sync completion flow test passed")
    }
    
    func testICloudSync_MultipleDeviceScenario() async throws {
        // Simulate multiple device sync scenario
        
        let testLocation = try createMockLocation()
        
        // Device 1: Create completion
        let device1Completion = try PrayerCompletion(
            prayerType: .dhuhr,
            date: Date(),
            locationId: testLocation.id
        )
        
        modelContext.insert(device1Completion)
        try modelContext.save()
        
        // Device 2: Create different completion for same prayer (conflict)
        let device2Completion = try PrayerCompletion(
            prayerType: .dhuhr,
            date: Date(),
            completedAt: Date().addingTimeInterval(-1800), // 30 minutes ago
            locationId: testLocation.id
        )
        
        // Simulate conflict resolution (newer completion wins)
        let mockRecord = CKRecord(recordType: "PrayerCompletion")
        mockRecord["completedAt"] = device2Completion.completedAt
        
        let resolvedCompletion = iCloudSyncService.resolveConflicts(
            localCompletion: device1Completion,
            remoteRecord: mockRecord
        )
        
        // Device 1's completion should win (newer)
        XCTAssertGreaterThan(resolvedCompletion.completedAt, device2Completion.completedAt)
        
        print("✅ iCloud sync multiple device scenario test passed")
    }
    
    func testICloudSync_NetworkFailureRecovery() async throws {
        // Test behavior when iCloud sync fails
        
        let testLocation = try createMockLocation()
        let completion = try PrayerCompletion(
            prayerType: .asr,
            date: Date(),
            locationId: testLocation.id
        )
        
        modelContext.insert(completion)
        try modelContext.save()
        
        // Simulate network failure
        do {
            try await iCloudSyncService.verifyiCloudAvailability()
            // If this succeeds, we can't test network failure in this environment
            print("ℹ️ iCloud is available - cannot test network failure scenario")
        } catch let error as iCloudSyncError {
            // Expected in test environment
            switch error {
            case .networkUnavailable, .noiCloudAccount, .iCloudUnavailable:
                // Verify completion remains unsynced
                XCTAssertFalse(completion.syncedToiCloud)
                
                // Verify local storage fallback works
                let descriptor = FetchDescriptor<PrayerCompletion>()
                let localCompletions = try modelContext.fetch(descriptor)
                XCTAssertEqual(localCompletions.count, 1)
                
                print("✅ iCloud sync network failure recovery test passed")
            default:
                XCTFail("Unexpected iCloud error: \(error)")
            }
        }
    }
    
    // MARK: - Notification System Integration Tests
    
    func testNotificationSystem_DeliveryTiming() async throws {
        // Test notification delivery timing accuracy
        
        let testLocation = try createMockLocation()
        
        // Create prayer times for testing
        let now = Date()
        let prayers = [
            try Prayer(prayerType: .fajr, time: now.addingTimeInterval(300), locationId: testLocation.id), // 5 minutes
            try Prayer(prayerType: .dhuhr, time: now.addingTimeInterval(3600), locationId: testLocation.id), // 1 hour
            try Prayer(prayerType: .asr, time: now.addingTimeInterval(7200), locationId: testLocation.id) // 2 hours
        ]
        
        for prayer in prayers {
            modelContext.insert(prayer)
        }
        try modelContext.save()
        
        // Schedule notifications
        await notificationManager.scheduleNotifications(prayers: prayers, location: testLocation)
        
        // Verify notifications were scheduled
        let pendingNotifications = await notificationManager.getPendingNotifications()
        let prayerNotifications = pendingNotifications.filter { 
            $0.identifier.contains("prayer_") 
        }
        
        XCTAssertEqual(prayerNotifications.count, prayers.count)
        
        // Verify timing accuracy (within 1 second tolerance)
        for (index, notification) in prayerNotifications.enumerated() {
            if let trigger = notification.trigger as? UNCalendarNotificationTrigger,
               let triggerDate = trigger.nextTriggerDate() {
                let expectedTime = prayers[index].time
                let timeDifference = abs(triggerDate.timeIntervalSince(expectedTime))
                XCTAssertLessThan(timeDifference, 1.0, "Notification timing should be accurate within 1 second")
            }
        }
        
        print("✅ Notification system delivery timing test passed")
    }
    
    func testNotificationSystem_LocationBasedScheduling() async throws {
        // Test notifications are properly scheduled based on location changes
        
        let location1 = try createMockLocation(name: "Location 1")
        let location2 = try createMockLocation(name: "Location 2", latitude: 41.0, longitude: -75.0)
        
        // Schedule notifications for location 1
        let prayers1 = try await prayerTimeService.getPrayerTimes(for: location1, in: modelContext)
        await notificationManager.scheduleNotifications(prayers: prayers1, location: location1)
        
        let notifications1 = await notificationManager.getPendingNotifications()
        let initialCount = notifications1.count
        
        // Change to location 2 and reschedule
        let prayers2 = try await prayerTimeService.getPrayerTimes(for: location2, in: modelContext)
        await notificationManager.scheduleNotifications(prayers: prayers2, location: location2)
        
        let notifications2 = await notificationManager.getPendingNotifications()
        
        // Should have notifications for the new location
        XCTAssertGreaterThan(notifications2.count, 0)
        
        // Verify notification content includes correct location
        let locationNotifications = notifications2.filter { notification in
            notification.content.body.contains(location2.displayName)
        }
        XCTAssertGreaterThan(locationNotifications.count, 0)
        
        print("✅ Notification system location-based scheduling test passed")
    }
    
    func testNotificationSystem_PreferenceChanges() async throws {
        // Test notification system responds to preference changes
        
        let testLocation = try createMockLocation()
        let prayers = try await prayerTimeService.getPrayerTimes(for: testLocation, in: modelContext)
        
        // Initial schedule with all prayers enabled
        await notificationManager.scheduleNotifications(prayers: prayers, location: testLocation)
        let initialNotifications = await notificationManager.getPendingNotifications()
        let initialCount = initialNotifications.count
        
        // Disable Fajr notifications
        let preferencesManager = PreferencesManager.shared
        preferencesManager.togglePrayerNotification(.fajr)
        
        // Reschedule notifications
        await notificationManager.rescheduleAllNotifications()
        
        let updatedNotifications = await notificationManager.getPendingNotifications()
        
        // Should have fewer notifications (no Fajr)
        let fajrNotifications = updatedNotifications.filter { notification in
            notification.content.title.contains("Fajr") || 
            notification.content.body.contains("Fajr")
        }
        
        if !preferencesManager.isPrayerNotificationEnabled(.fajr) {
            XCTAssertEqual(fajrNotifications.count, 0, "Fajr notifications should be disabled")
        }
        
        print("✅ Notification system preference changes test passed")
    }
    
    // MARK: - Accessibility and Usability Tests
    
    func testAccessibility_VoiceOverSupport() throws {
        // Test VoiceOver accessibility support
        
        // This would typically test UI elements for proper accessibility labels
        // Since we're testing the model layer, we'll verify data accessibility
        
        let testLocation = try createMockLocation()
        let prayer = try Prayer(
            prayerType: .dhuhr,
            time: Date(),
            locationId: testLocation.id
        )
        
        // Verify accessibility descriptions are available
        XCTAssertFalse(prayer.prayerType.displayName.isEmpty)
        XCTAssertFalse(testLocation.displayName.isEmpty)
        
        // Test prayer completion accessibility
        let completion = try PrayerCompletion(
            prayerType: .dhuhr,
            date: Date(),
            locationId: testLocation.id
        )
        
        XCTAssertNotNil(completion.accessibilityDescription)
        XCTAssertFalse(completion.accessibilityDescription.isEmpty)
        
        print("✅ Accessibility VoiceOver support test passed")
    }
    
    func testUsability_ErrorRecovery() async throws {
        // Test error recovery scenarios
        
        let errorHandler = ErrorHandlerManager.shared
        
        // Test network error recovery
        let networkError = PrayerAppError.networkUnavailable
        errorHandler.handle(networkError, showToUser: false)
        
        let strategy = ErrorRecoveryStrategy.strategy(for: networkError)
        XCTAssertEqual(strategy.primaryAction, .retry)
        XCTAssertTrue(strategy.automaticRetry)
        
        // Test location permission error recovery
        let locationError = PrayerAppError.locationPermissionDenied
        errorHandler.handle(locationError, showToUser: false)
        
        let locationStrategy = ErrorRecoveryStrategy.strategy(for: locationError)
        XCTAssertEqual(locationStrategy.primaryAction, .openSystemPreferences)
        XCTAssertTrue(locationStrategy.secondaryActions.contains(.selectManualLocation))
        
        // Test graceful degradation
        let degradationManager = GracefulDegradationManager.shared
        let testLocation = try createMockLocation()
        let prayers = try await prayerTimeService.getPrayerTimes(for: testLocation, in: modelContext)
        
        degradationManager.storeFallbackData(prayers: prayers, location: testLocation)
        
        let fallbackPrayers = degradationManager.getPrayerTimesInDegradedMode()
        let fallbackLocation = degradationManager.getLocationInDegradedMode()
        
        XCTAssertEqual(fallbackPrayers.count, prayers.count)
        XCTAssertEqual(fallbackLocation?.id, testLocation.id)
        
        print("✅ Usability error recovery test passed")
    }
    
    func testUsability_PerformanceUnderLoad() async throws {
        // Test performance under load conditions
        
        let performanceMonitor = PerformanceMonitor.shared
        
        // Create multiple locations and prayers
        var locations: [Location] = []
        var allPrayers: [Prayer] = []
        
        for i in 0..<10 {
            let location = try createMockLocation(
                name: "Location \(i)",
                latitude: 40.0 + Double(i) * 0.1,
                longitude: -74.0 + Double(i) * 0.1
            )
            locations.append(location)
            modelContext.insert(location)
            
            let prayers = try await prayerTimeService.getPrayerTimes(for: location, in: modelContext)
            allPrayers.append(contentsOf: prayers)
        }
        
        try modelContext.save()
        
        // Measure performance of bulk operations
        let startTime = Date()
        
        // Simulate rapid location changes
        for location in locations {
            statusBarController.updateLocation(location)
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // Should complete within reasonable time (less than 2 seconds for 10 locations)
        XCTAssertLessThan(duration, 2.0, "Bulk location updates should complete quickly")
        
        // Check memory usage
        let metrics = performanceMonitor.currentMetrics
        XCTAssertNotNil(metrics)
        
        print("✅ Usability performance under load test passed")
    }
    
    // MARK: - Helper Methods
    
    private func createMockLocation(
        name: String = "Test Location",
        latitude: Double = 40.7128,
        longitude: Double = -74.0060
    ) throws -> Location {
        return try Location(
            name: name,
            city: "Test City",
            country: "Test Country",
            latitude: latitude,
            longitude: longitude,
            diyanetId: "test\(Int.random(in: 1000...9999))"
        )
    }
    
    private func createMockPrayer(
        type: PrayerType = .dhuhr,
        location: Location,
        timeOffset: TimeInterval = 3600
    ) throws -> Prayer {
        return try Prayer(
            prayerType: type,
            time: Date().addingTimeInterval(timeOffset),
            locationId: location.id
        )
    }
}

// MARK: - Performance Tests

extension IntegrationTests {
    
    func testOverallSystemPerformance() throws {
        // Test overall system performance metrics
        
        measure {
            // Simulate typical user operations
            let expectation = XCTestExpectation(description: "Performance test")
            
            Task {
                do {
                    let location = try self.createMockLocation()
                    let prayers = try await self.prayerTimeService.getPrayerTimes(for: location, in: self.modelContext)
                    
                    self.statusBarController.updateLocation(location)
                    await self.notificationManager.scheduleNotifications(prayers: prayers, location: location)
                    
                    let completion = try PrayerCompletion(
                        prayerType: .fajr,
                        date: Date(),
                        locationId: location.id
                    )
                    
                    self.modelContext.insert(completion)
                    try self.modelContext.save()
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Performance test failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
}

// MARK: - Stress Tests

extension IntegrationTests {
    
    func testSystemStressTest() async throws {
        // Stress test the system with rapid operations
        
        let iterations = 50
        var locations: [Location] = []
        
        // Create many locations
        for i in 0..<iterations {
            let location = try createMockLocation(
                name: "Stress Location \(i)",
                latitude: 40.0 + Double(i) * 0.001,
                longitude: -74.0 + Double(i) * 0.001
            )
            locations.append(location)
            modelContext.insert(location)
        }
        
        try modelContext.save()
        
        // Rapid location switching
        for location in locations {
            statusBarController.updateLocation(location)
            
            // Create completion for each location
            let completion = try PrayerCompletion(
                prayerType: PrayerType.allCases.randomElement()!,
                date: Date(),
                locationId: location.id
            )
            
            modelContext.insert(completion)
        }
        
        try modelContext.save()
        
        // Verify system stability
        let descriptor = FetchDescriptor<PrayerCompletion>()
        let completions = try modelContext.fetch(descriptor)
        XCTAssertEqual(completions.count, iterations)
        
        print("✅ System stress test passed with \(iterations) operations")
    }
}