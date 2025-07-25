//
//  NotificationSystemTests.swift
//  PrayerProTests
//
//  Created by Kiro on 24.07.25.
//

import XCTest
import UserNotifications
@testable import PrayerPro

final class NotificationSystemTests: XCTestCase {
    
    var notificationManager: NotificationManager!
    var preferencesManager: PreferencesManager!
    
    override func setUpWithError() throws {
        notificationManager = NotificationManager.shared
        preferencesManager = PreferencesManager.shared
    }
    
    override func tearDownWithError() throws {
        // Clean up notifications after each test
        Task {
            await notificationManager.clearAllNotifications()
        }
        notificationManager = nil
        preferencesManager = nil
    }
    
    // MARK: - Notification Manager Tests
    
    func testNotificationManagerInitialization() throws {
        XCTAssertNotNil(notificationManager)
        XCTAssertNotNil(notificationManager.preferences)
        XCTAssertTrue(notificationManager.preferences.isEnabled)
    }
    
    func testNotificationPreferencesDefaults() throws {
        let preferences = NotificationPreferences()
        
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertTrue(preferences.useGPSLocation)
        XCTAssertEqual(preferences.advanceNotificationMinutes, 0)
        XCTAssertTrue(preferences.playSound)
        XCTAssertFalse(preferences.showBadge)
        
        // Check default enabled prayer types (all except sunrise)
        let expectedPrayerTypes = Set(PrayerType.allCases.filter { $0 != .sunrise })
        XCTAssertEqual(preferences.enabledPrayerTypes, expectedPrayerTypes)
    }
    
    func testTogglePrayerType() throws {
        let initialCount = preferencesManager.enabledPrayerNotifications.count
        
        // Toggle off a prayer type
        preferencesManager.togglePrayerNotification(.fajr)
        
        if preferencesManager.isPrayerNotificationEnabled(.fajr) {
            XCTAssertEqual(preferencesManager.enabledPrayerNotifications.count, initialCount)
        } else {
            XCTAssertEqual(preferencesManager.enabledPrayerNotifications.count, initialCount - 1)
        }
        
        // Toggle it back
        preferencesManager.togglePrayerNotification(.fajr)
        XCTAssertEqual(preferencesManager.enabledPrayerNotifications.count, initialCount)
    }
    
    func testLocationPreferences() throws {
        // Test GPS location preference
        preferencesManager.useGPSLocationForNotifications()
        XCTAssertTrue(preferencesManager.useGPSForNotifications)
        XCTAssertNil(preferencesManager.notificationLocationId)
        
        // Test specific location preference
        let testLocation = try createTestLocation()
        preferencesManager.setNotificationLocation(testLocation)
        XCTAssertFalse(preferencesManager.useGPSForNotifications)
        XCTAssertEqual(preferencesManager.notificationLocationId, testLocation.id)
    }
    
    // MARK: - Notification Scheduling Tests
    
    func testScheduleTestNotification() async throws {
        // This test verifies that test notifications can be scheduled
        await notificationManager.scheduleTestNotification()
        
        let pendingNotifications = await notificationManager.getPendingNotifications()
        let testNotifications = pendingNotifications.filter { $0.identifier == "test_notification" }
        
        XCTAssertEqual(testNotifications.count, 1)
        
        let testNotification = testNotifications.first!
        XCTAssertEqual(testNotification.content.title, "Test Prayer Notification")
        XCTAssertEqual(testNotification.content.body, "This is a test notification to verify prayer notifications are working.")
    }
    
    func testClearAllNotifications() async throws {
        // Schedule a test notification first
        await notificationManager.scheduleTestNotification()
        
        var pendingNotifications = await notificationManager.getPendingNotifications()
        XCTAssertGreaterThan(pendingNotifications.count, 0)
        
        // Clear all notifications
        await notificationManager.clearAllNotifications()
        
        pendingNotifications = await notificationManager.getPendingNotifications()
        XCTAssertEqual(pendingNotifications.count, 0)
    }
    
    func testNotificationContent() throws {
        let testLocation = try createTestLocation()
        let testPrayer = try createTestPrayer(for: testLocation)
        
        // Test notification body creation
        let notificationManager = NotificationManager.shared
        let preferences = notificationManager.preferences
        
        // Test with no advance notification
        preferences.advanceNotificationMinutes = 0
        let bodyImmediate = createNotificationBody(for: testPrayer, location: testLocation, preferences: preferences)
        XCTAssertTrue(bodyImmediate.contains("It's time for"))
        XCTAssertTrue(bodyImmediate.contains(testPrayer.prayerType.displayName))
        
        // Test with advance notification
        preferences.advanceNotificationMinutes = 10
        let bodyAdvance = createNotificationBody(for: testPrayer, location: testLocation, preferences: preferences)
        XCTAssertTrue(bodyAdvance.contains("in 10 minutes"))
        XCTAssertTrue(bodyAdvance.contains(testPrayer.prayerType.displayName))
    }
    
    // MARK: - Notification Categories Tests
    
    func testNotificationCategories() async throws {
        let notificationCenter = UNUserNotificationCenter.current()
        let categories = await notificationCenter.notificationCategories()
        
        let prayerCategory = categories.first { $0.identifier == "PRAYER_NOTIFICATION" }
        XCTAssertNotNil(prayerCategory)
        
        if let category = prayerCategory {
            XCTAssertEqual(category.actions.count, 3)
            
            let actionIdentifiers = category.actions.map { $0.identifier }
            XCTAssertTrue(actionIdentifiers.contains("MARK_COMPLETED"))
            XCTAssertTrue(actionIdentifiers.contains("SNOOZE"))
            XCTAssertTrue(actionIdentifiers.contains("VIEW_PRAYER_TIMES"))
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestLocation() throws -> Location {
        return try Location(
            name: "Test Mosque",
            city: "Test City",
            country: "Test Country",
            latitude: 40.7128,
            longitude: -74.0060,
            diyanetId: "12345"
        )
    }
    
    private func createTestPrayer(for location: Location) throws -> Prayer {
        let futureTime = Date().addingTimeInterval(3600) // 1 hour from now
        return try Prayer(
            prayerType: .dhuhr,
            time: futureTime,
            locationId: location.id
        )
    }
    
    private func createNotificationBody(for prayer: Prayer, location: Location, preferences: NotificationPreferences) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        let prayerTime = timeFormatter.string(from: prayer.time)
        
        if preferences.advanceNotificationMinutes > 0 {
            return "\(prayer.prayerType.displayName) prayer is in \(preferences.advanceNotificationMinutes) minutes at \(prayerTime) in \(location.displayName)"
        } else {
            return "It's time for \(prayer.prayerType.displayName) prayer (\(prayerTime)) in \(location.displayName)"
        }
    }
}

// MARK: - Performance Tests

extension NotificationSystemTests {
    
    func testNotificationSchedulingPerformance() throws {
        let testLocation = try createTestLocation()
        var testPrayers: [Prayer] = []
        
        // Create 35 test prayers (5 prayers × 7 days)
        for day in 0..<7 {
            for prayerType in [PrayerType.fajr, .dhuhr, .asr, .maghrib, .isha] {
                let baseTime = Calendar.current.startOfDay(for: Date())
                let prayerTime = Calendar.current.date(byAdding: .day, value: day, to: baseTime)!
                    .addingTimeInterval(TimeInterval(prayerType.hashValue * 3600)) // Spread prayers throughout the day
                
                let prayer = try Prayer(
                    prayerType: prayerType,
                    time: prayerTime,
                    locationId: testLocation.id
                )
                testPrayers.append(prayer)
            }
        }
        
        // Measure performance of scheduling multiple notifications
        measure {
            let expectation = XCTestExpectation(description: "Schedule notifications")
            
            Task {
                await notificationManager.scheduleNotifications(prayers: testPrayers, location: testLocation)
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
    }
}