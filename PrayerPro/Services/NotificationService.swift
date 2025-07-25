//
//  NotificationService.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import UserNotifications
import SwiftData
import AppKit

// MARK: - Notification Preferences

struct NotificationPreferences: Codable {
    var isEnabled: Bool = true
    var enabledPrayerTypes: Set<PrayerType> = Set(PrayerType.allCases.filter { $0 != .sunrise })
    var selectedLocationId: UUID?
    var useGPSLocation: Bool = true
    var notificationSound: NotificationSound = .default
    var advanceNotificationMinutes: Int = 0
    var showInNotificationCenter: Bool = true
    var playSound: Bool = true
    var showBadge: Bool = false
    
    enum NotificationSound: String, CaseIterable, Codable {
        case `default` = "default"
        case none = "none"
        case chime = "chime"
        case bell = "bell"
        
        var displayName: String {
            switch self {
            case .default: return "Default"
            case .none: return "None"
            case .chime: return "Chime"
            case .bell: return "Bell"
            }
        }
        
        var unSound: UNNotificationSound? {
            switch self {
            case .default: return .default
            case .none: return nil
            case .chime: return UNNotificationSound(named: UNNotificationSoundName("chime.aiff"))
            case .bell: return UNNotificationSound(named: UNNotificationSoundName("bell.aiff"))
            }
        }
    }
}

// MARK: - Notification Manager

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private let userDefaults = UserDefaults.standard
    private let notificationCenter = UNUserNotificationCenter.current()
    private let preferencesKey = "NotificationPreferences"
    
    // Published properties for UI binding
    @Published var preferences: NotificationPreferences {
        didSet {
            savePreferences()
            Task {
                await rescheduleAllNotifications()
            }
        }
    }
    
    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined
    var isPermissionGranted: Bool { permissionStatus == .authorized }
    
    private init() {
        // Initialize preferences first
        self.preferences = NotificationPreferences()
        
        // Load saved preferences
        self.preferences = loadPreferences()
        
        // Set up notification center delegate
        notificationCenter.delegate = NotificationDelegate.shared
        
        // Set up notification categories
        setupNotificationCategories()
        
        // Check initial permission status
        Task {
            await updatePermissionStatus()
        }
    }
    
    private func setupNotificationCategories() {
        // Create actions for prayer notifications
        let markCompletedAction = UNNotificationAction(
            identifier: "MARK_COMPLETED",
            title: "Mark as Completed",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Remind in 5 min",
            options: []
        )
        
        let viewPrayerTimesAction = UNNotificationAction(
            identifier: "VIEW_PRAYER_TIMES",
            title: "View Prayer Times",
            options: [.foreground]
        )
        
        // Create prayer notification category
        let prayerCategory = UNNotificationCategory(
            identifier: "PRAYER_NOTIFICATION",
            actions: [markCompletedAction, snoozeAction, viewPrayerTimesAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Register categories
        notificationCenter.setNotificationCategories([prayerCategory])
    }
    
    // MARK: - Permission Management
    
    func requestNotificationPermission() async -> Bool {
        print("🔔 Requesting notification permission...")
        
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await notificationCenter.requestAuthorization(options: options)
            
            print("🔔 Permission request result: \(granted)")
            
            await updatePermissionStatus()
            
            print("🔔 Updated permission status: \(permissionStatus)")
            
            // Post notification about permission change
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .notificationPermissionChanged,
                    object: nil,
                    userInfo: ["granted": granted]
                )
            }
            
            return granted
        } catch {
            print("🔔 Notification permission error: \(error)")
            await updatePermissionStatus()
            return false
        }
    }
    
    @MainActor
    func updatePermissionStatus() async {
        let settings = await notificationCenter.notificationSettings()
        let oldStatus = self.permissionStatus
        self.permissionStatus = settings.authorizationStatus
        
        print("🔔 Permission status updated: \(oldStatus) -> \(self.permissionStatus)")
        print("🔔 Is permission granted: \(isPermissionGranted)")
    }
    
    func openNotificationSettings() {
        // Try to open System Settings (macOS 13+) first, then fall back to System Preferences
        if #available(macOS 13.0, *) {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
            NSWorkspace.shared.open(url)
        } else {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Notification Scheduling
    
    func scheduleAllNotifications() async {
        guard isPermissionGranted && preferences.isEnabled else {
            await clearAllNotifications()
            return
        }
        
        // Post notification to request prayer times from the main app
        // The main app will handle getting location and prayer times, then call scheduleNotifications
        NotificationCenter.default.post(
            name: .requestPrayerTimesForNotifications,
            object: nil,
            userInfo: nil
        )
    }
    
    /// Schedule notifications with provided prayer times and location
    func scheduleNotifications(prayers: [Prayer], location: Location) async {
        guard isPermissionGranted && preferences.isEnabled else {
            await clearAllNotifications()
            return
        }
        
        await scheduleNotifications(for: prayers, location: location)
    }
    
    private func scheduleNotifications(for prayers: [Prayer], location: Location) async {
        // Clear existing notifications
        await clearAllNotifications()
        
        let calendar = Calendar.current
        let now = Date()
        
        // Schedule notifications for the next 7 days
        for dayOffset in 0..<7 {
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            
            let dayPrayers = prayers.filter { calendar.isDate($0.time, inSameDayAs: targetDate) }
            
            for prayer in dayPrayers {
                // Skip if this prayer type is disabled
                guard preferences.enabledPrayerTypes.contains(prayer.prayerType) else { continue }
                
                // Skip if prayer time has already passed (for today only)
                if dayOffset == 0 && prayer.time < now { continue }
                
                await scheduleNotification(for: prayer, location: location)
            }
        }
        
        print("Scheduled notifications for \(prayers.count) prayers")
    }
    
    private func scheduleNotification(for prayer: Prayer, location: Location) async {
        let content = UNMutableNotificationContent()
        content.title = "Prayer Time"
        content.body = createNotificationBody(for: prayer, location: location)
        content.categoryIdentifier = "PRAYER_NOTIFICATION"
        content.userInfo = [
            "prayerId": prayer.id.uuidString,
            "prayerType": prayer.prayerType.rawValue,
            "locationId": location.id.uuidString
        ]
        
        // Configure sound
        if preferences.playSound {
            content.sound = preferences.notificationSound.unSound
        }
        
        // Configure badge
        if preferences.showBadge {
            content.badge = 1
        }
        
        // Calculate notification time (with advance notification if set)
        let notificationTime = prayer.time.addingTimeInterval(-TimeInterval(preferences.advanceNotificationMinutes * 60))
        
        // Don't schedule notifications for past times
        guard notificationTime > Date() else { return }
        
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "prayer_\(prayer.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule notification for \(prayer.prayerType.displayName): \(error)")
        }
    }
    
    private func createNotificationBody(for prayer: Prayer, location: Location) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        let prayerTime = timeFormatter.string(from: prayer.time)
        
        if preferences.advanceNotificationMinutes > 0 {
            return "\(prayer.prayerType.displayName) prayer is in \(preferences.advanceNotificationMinutes) minutes at \(prayerTime) in \(location.displayName)"
        } else {
            return "It's time for \(prayer.prayerType.displayName) prayer (\(prayerTime)) in \(location.displayName)"
        }
    }
    
    // MARK: - Notification Management
    
    func rescheduleAllNotifications() async {
        await scheduleAllNotifications()
    }
    
    func clearAllNotifications() async {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }
    
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }
    
    func getDeliveredNotifications() async -> [UNNotification] {
        return await notificationCenter.deliveredNotifications()
    }
    
    // MARK: - Location Management
    
    private func getNotificationLocation() async -> Location? {
        // If using GPS location, get current GPS location
        if preferences.useGPSLocation {
            do {
                return try await LocationService.shared.getCurrentLocation()
            } catch {
                print("Failed to get GPS location for notifications: \(error)")
                return nil
            }
        }
        
        // If using a specific favorite location, get it from preferences
        if let locationId = preferences.selectedLocationId {
            // We need to get this from the data context - for now return nil
            // This will be handled by the calling code that has access to ModelContext
            return nil
        }
        
        return nil
    }
    
    private func getPrayerTimes(for location: Location) async -> [Prayer]? {
        // We need ModelContext to get prayer times, so this will be handled differently
        // The calling code will need to provide the context
        return nil
    }
    
    // MARK: - Preferences Management
    
    private func loadPreferences() -> NotificationPreferences {
        guard let data = userDefaults.data(forKey: preferencesKey),
              let preferences = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else {
            return NotificationPreferences()
        }
        return preferences
    }
    
    private func savePreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        userDefaults.set(data, forKey: preferencesKey)
    }
    
    // MARK: - Prayer Type Management
    
    func togglePrayerType(_ prayerType: PrayerType) {
        if preferences.enabledPrayerTypes.contains(prayerType) {
            preferences.enabledPrayerTypes.remove(prayerType)
        } else {
            preferences.enabledPrayerTypes.insert(prayerType)
        }
    }
    
    func isPrayerTypeEnabled(_ prayerType: PrayerType) -> Bool {
        return preferences.enabledPrayerTypes.contains(prayerType)
    }
    
    // MARK: - Location Selection
    
    func setNotificationLocation(to location: Location) {
        preferences.selectedLocationId = location.id
        preferences.useGPSLocation = false
    }
    
    func useGPSForNotifications() {
        preferences.useGPSLocation = true
        preferences.selectedLocationId = nil
    }
    
    // MARK: - Testing and Debug
    
    func scheduleTestNotification() async {
        print("🔔 Scheduling test notification...")
        print("🔔 Permission granted: \(isPermissionGranted)")
        
        guard isPermissionGranted else {
            print("🔔 Cannot schedule test notification - permission not granted")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Test Prayer Notification"
        content.body = "This is a test notification to verify prayer notifications are working."
        content.sound = preferences.notificationSound.unSound
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test_notification", content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            print("🔔 Test notification scheduled successfully")
        } catch {
            print("🔔 Failed to schedule test notification: \(error)")
        }
    }
    
    // Debug function to check current notification settings
    func debugNotificationSettings() async {
        let settings = await notificationCenter.notificationSettings()
        print("🔔 === Notification Settings Debug ===")
        print("🔔 Authorization Status: \(settings.authorizationStatus)")
        print("🔔 Alert Setting: \(settings.alertSetting)")
        print("🔔 Badge Setting: \(settings.badgeSetting)")
        print("🔔 Sound Setting: \(settings.soundSetting)")
        print("🔔 Notification Center Setting: \(settings.notificationCenterSetting)")
        print("🔔 Lock Screen Setting: \(settings.lockScreenSetting)")
        #if !os(macOS)
        print("🔔 Car Play Setting: \(settings.carPlaySetting)")
        #endif
        print("🔔 === End Debug ===")
    }
}

// MARK: - Notification Delegate

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    private override init() {
        super.init()
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let userInfo = response.notification.request.content.userInfo
        
        // Extract prayer information
        guard let prayerIdString = userInfo["prayerId"] as? String,
              let prayerId = UUID(uuidString: prayerIdString),
              let prayerTypeString = userInfo["prayerType"] as? String,
              let prayerType = PrayerType(rawValue: prayerTypeString),
              let locationIdString = userInfo["locationId"] as? String,
              let locationId = UUID(uuidString: locationIdString) else {
            completionHandler()
            return
        }
        
        // Handle different actions
        switch response.actionIdentifier {
        case "MARK_COMPLETED":
            handleMarkCompleted(prayerId: prayerId, prayerType: prayerType, locationId: locationId)
            
        case "SNOOZE":
            handleSnooze(prayerId: prayerId, prayerType: prayerType, locationId: locationId)
            
        case "VIEW_PRAYER_TIMES":
            handleViewPrayerTimes(prayerId: prayerId, prayerType: prayerType)
            
        case UNNotificationDefaultActionIdentifier:
            // Default tap - show prayer times
            handleViewPrayerTimes(prayerId: prayerId, prayerType: prayerType)
            
        default:
            break
        }
        
        completionHandler()
    }
    
    private func handleMarkCompleted(prayerId: UUID, prayerType: PrayerType, locationId: UUID) {
        // Post notification to mark prayer as completed
        NotificationCenter.default.post(
            name: .markPrayerCompleted,
            object: nil,
            userInfo: [
                "prayerId": prayerId,
                "prayerType": prayerType,
                "locationId": locationId
            ]
        )
    }
    
    private func handleSnooze(prayerId: UUID, prayerType: PrayerType, locationId: UUID) {
        // Schedule a snooze notification in 5 minutes
        Task {
            let content = UNMutableNotificationContent()
            content.title = "Prayer Reminder"
            content.body = "Reminder: It's time for \(prayerType.displayName) prayer"
            content.sound = .default
            content.categoryIdentifier = "PRAYER_NOTIFICATION"
            content.userInfo = [
                "prayerId": prayerId.uuidString,
                "prayerType": prayerType.rawValue,
                "locationId": locationId.uuidString
            ]
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false) // 5 minutes
            let request = UNNotificationRequest(
                identifier: "snooze_\(prayerId.uuidString)",
                content: content,
                trigger: trigger
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("Failed to schedule snooze notification: \(error)")
            }
        }
    }
    
    private func handleViewPrayerTimes(prayerId: UUID, prayerType: PrayerType) {
        // Bring app to foreground and navigate to prayer times
        NSApp.activate(ignoringOtherApps: true)
        
        // Post notification to show main window and highlight the prayer
        NotificationCenter.default.post(
            name: .showPrayerFromNotification,
            object: nil,
            userInfo: ["prayerId": prayerId, "prayerType": prayerType]
        )
    }
}

// MARK: - Notification Scheduler

class NotificationScheduler {
    static let shared = NotificationScheduler()
    
    private let notificationManager = NotificationManager.shared
    private var schedulingTimer: Timer?
    
    private init() {
        setupSchedulingTimer()
        setupLocationChangeObserver()
    }
    
    // MARK: - Automatic Scheduling
    
    private func setupSchedulingTimer() {
        // Schedule notifications to be updated daily at midnight
        schedulingTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task {
                await self.notificationManager.rescheduleAllNotifications()
            }
        }
    }
    
    private func setupLocationChangeObserver() {
        // Listen for location changes to reschedule notifications
        NotificationCenter.default.addObserver(
            forName: .locationSelected,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await self.notificationManager.rescheduleAllNotifications()
            }
        }
    }
    
    // MARK: - Manual Scheduling
    
    func scheduleNotificationsForToday() async {
        await notificationManager.scheduleAllNotifications()
    }
    
    func scheduleNotificationsForWeek() async {
        await notificationManager.scheduleAllNotifications()
    }
    
    deinit {
        schedulingTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Extensions

extension Notification.Name {
    static let showPrayerFromNotification = Notification.Name("ShowPrayerFromNotification")
    static let notificationPermissionChanged = Notification.Name("NotificationPermissionChanged")
    static let notificationPreferencesChanged = Notification.Name("NotificationPreferencesChanged")
    static let requestPrayerTimesForNotifications = Notification.Name("RequestPrayerTimesForNotifications")
    static let markPrayerCompleted = Notification.Name("MarkPrayerCompleted")
}