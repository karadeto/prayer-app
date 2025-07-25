//
//  PreferencesManager.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftUI

// MARK: - Status Bar Widget Preferences

enum StatusBarDisplayFormat: String, CaseIterable, Identifiable {
    case countdown = "countdown"
    case nextPrayerTime = "nextPrayerTime"
    case nextPrayerName = "nextPrayerName"
    case iconAndCountdown = "iconAndCountdown"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .countdown:
            return "Countdown Only"
        case .nextPrayerTime:
            return "Next Prayer Time"
        case .nextPrayerName:
            return "Next Prayer Name"
        case .iconAndCountdown:
            return "Icon + Countdown"
        }
    }
    
    var description: String {
        switch self {
        case .countdown:
            return "Shows only the countdown timer (e.g., 2:30)"
        case .nextPrayerTime:
            return "Shows the next prayer time (e.g., Dhuhr 12:30)"
        case .nextPrayerName:
            return "Shows only the prayer name (e.g., Dhuhr)"
        case .iconAndCountdown:
            return "Shows prayer icon and countdown (e.g., ☀️ 2:30)"
        }
    }
}

enum StatusBarUpdateFrequency: Int, CaseIterable, Identifiable {
    case everySecond = 1
    case every5Seconds = 5
    case every10Seconds = 10
    case every30Seconds = 30
    case everyMinute = 60
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .everySecond:
            return "Every Second"
        case .every5Seconds:
            return "Every 5 Seconds"
        case .every10Seconds:
            return "Every 10 Seconds"
        case .every30Seconds:
            return "Every 30 Seconds"
        case .everyMinute:
            return "Every Minute"
        }
    }
    
    var description: String {
        switch self {
        case .everySecond:
            return "Most accurate, higher battery usage"
        case .every5Seconds:
            return "Good balance of accuracy and efficiency"
        case .every10Seconds:
            return "Moderate accuracy, good efficiency"
        case .every30Seconds:
            return "Lower accuracy, better efficiency"
        case .everyMinute:
            return "Lowest accuracy, best battery life"
        }
    }
}

// MARK: - Preferences Manager

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Status Bar Widget Preferences
    
    @Published var isStatusBarWidgetEnabled: Bool {
        didSet {
            userDefaults.set(isStatusBarWidgetEnabled, forKey: Keys.statusBarWidgetEnabled)
            NotificationCenter.default.post(
                name: .statusBarWidgetPreferenceChanged,
                object: nil,
                userInfo: ["isEnabled": isStatusBarWidgetEnabled]
            )
        }
    }
    
    @Published var statusBarDisplayFormat: StatusBarDisplayFormat {
        didSet {
            userDefaults.set(statusBarDisplayFormat.rawValue, forKey: Keys.statusBarDisplayFormat)
            NotificationCenter.default.post(
                name: .statusBarDisplayFormatChanged,
                object: nil,
                userInfo: ["format": statusBarDisplayFormat]
            )
        }
    }
    
    @Published var statusBarUpdateFrequency: StatusBarUpdateFrequency {
        didSet {
            userDefaults.set(statusBarUpdateFrequency.rawValue, forKey: Keys.statusBarUpdateFrequency)
            NotificationCenter.default.post(
                name: .statusBarUpdateFrequencyChanged,
                object: nil,
                userInfo: ["frequency": statusBarUpdateFrequency]
            )
        }
    }
    
    @Published var showStatusBarIcon: Bool {
        didSet {
            userDefaults.set(showStatusBarIcon, forKey: Keys.showStatusBarIcon)
            NotificationCenter.default.post(
                name: .statusBarIconPreferenceChanged,
                object: nil,
                userInfo: ["showIcon": showStatusBarIcon]
            )
        }
    }
    
    @Published var statusBarClickAction: StatusBarClickAction {
        didSet {
            userDefaults.set(statusBarClickAction.rawValue, forKey: Keys.statusBarClickAction)
        }
    }
    
    // MARK: - Notification Preferences
    
    @Published var notificationsEnabled: Bool {
        didSet {
            userDefaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            NotificationCenter.default.post(
                name: .notificationPreferencesChanged,
                object: nil,
                userInfo: ["notificationsEnabled": notificationsEnabled]
            )
        }
    }
    
    @Published var enabledPrayerNotifications: Set<PrayerType> {
        didSet {
            let rawValues = enabledPrayerNotifications.map { $0.rawValue }
            userDefaults.set(rawValues, forKey: Keys.enabledPrayerNotifications)
            NotificationCenter.default.post(
                name: .notificationPreferencesChanged,
                object: nil,
                userInfo: ["enabledPrayerNotifications": enabledPrayerNotifications]
            )
        }
    }
    
    @Published var notificationLocationId: UUID? {
        didSet {
            if let locationId = notificationLocationId {
                userDefaults.set(locationId.uuidString, forKey: Keys.notificationLocationId)
            } else {
                userDefaults.removeObject(forKey: Keys.notificationLocationId)
            }
            NotificationCenter.default.post(
                name: .notificationPreferencesChanged,
                object: nil,
                userInfo: ["notificationLocationId": notificationLocationId]
            )
        }
    }
    
    @Published var useGPSForNotifications: Bool {
        didSet {
            userDefaults.set(useGPSForNotifications, forKey: Keys.useGPSForNotifications)
            NotificationCenter.default.post(
                name: .notificationPreferencesChanged,
                object: nil,
                userInfo: ["useGPSForNotifications": useGPSForNotifications]
            )
        }
    }
    
    @Published var notificationAdvanceMinutes: Int {
        didSet {
            userDefaults.set(notificationAdvanceMinutes, forKey: Keys.notificationAdvanceMinutes)
            NotificationCenter.default.post(
                name: .notificationPreferencesChanged,
                object: nil,
                userInfo: ["notificationAdvanceMinutes": notificationAdvanceMinutes]
            )
        }
    }
    
    @Published var notificationSound: String {
        didSet {
            userDefaults.set(notificationSound, forKey: Keys.notificationSound)
            NotificationCenter.default.post(
                name: .notificationPreferencesChanged,
                object: nil,
                userInfo: ["notificationSound": notificationSound]
            )
        }
    }
    
    // MARK: - General App Preferences
    
    @Published var selectedLocationId: UUID? {
        didSet {
            if let locationId = selectedLocationId {
                userDefaults.set(locationId.uuidString, forKey: Keys.selectedLocationId)
            } else {
                userDefaults.removeObject(forKey: Keys.selectedLocationId)
            }
        }
    }
    
    @Published var useGPSLocation: Bool {
        didSet {
            userDefaults.set(useGPSLocation, forKey: Keys.useGPSLocation)
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved preferences or set defaults
        self.isStatusBarWidgetEnabled = userDefaults.object(forKey: Keys.statusBarWidgetEnabled) as? Bool ?? true
        
        let displayFormatString = userDefaults.string(forKey: Keys.statusBarDisplayFormat) ?? StatusBarDisplayFormat.iconAndCountdown.rawValue
        self.statusBarDisplayFormat = StatusBarDisplayFormat(rawValue: displayFormatString) ?? .iconAndCountdown
        
        let updateFrequencyInt = userDefaults.object(forKey: Keys.statusBarUpdateFrequency) as? Int ?? StatusBarUpdateFrequency.everySecond.rawValue
        self.statusBarUpdateFrequency = StatusBarUpdateFrequency(rawValue: updateFrequencyInt) ?? .everySecond
        
        self.showStatusBarIcon = userDefaults.object(forKey: Keys.showStatusBarIcon) as? Bool ?? true
        
        let clickActionString = userDefaults.string(forKey: Keys.statusBarClickAction) ?? StatusBarClickAction.showPopover.rawValue
        self.statusBarClickAction = StatusBarClickAction(rawValue: clickActionString) ?? .showPopover
        
        // Notification preferences
        self.notificationsEnabled = userDefaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        
        let enabledPrayerNotificationsRaw = userDefaults.array(forKey: Keys.enabledPrayerNotifications) as? [String] ?? PrayerType.allCases.filter { $0 != .sunrise }.map { $0.rawValue }
        self.enabledPrayerNotifications = Set(enabledPrayerNotificationsRaw.compactMap { PrayerType(rawValue: $0) })
        
        if let notificationLocationIdString = userDefaults.string(forKey: Keys.notificationLocationId) {
            self.notificationLocationId = UUID(uuidString: notificationLocationIdString)
        } else {
            self.notificationLocationId = nil
        }
        
        self.useGPSForNotifications = userDefaults.object(forKey: Keys.useGPSForNotifications) as? Bool ?? true
        self.notificationAdvanceMinutes = userDefaults.object(forKey: Keys.notificationAdvanceMinutes) as? Int ?? 0
        self.notificationSound = userDefaults.string(forKey: Keys.notificationSound) ?? "default"
        
        // General preferences
        if let locationIdString = userDefaults.string(forKey: Keys.selectedLocationId) {
            self.selectedLocationId = UUID(uuidString: locationIdString)
        } else {
            self.selectedLocationId = nil
        }
        
        self.useGPSLocation = userDefaults.object(forKey: Keys.useGPSLocation) as? Bool ?? true
    }
    
    // MARK: - Notification Helper Methods
    
    func togglePrayerNotification(_ prayerType: PrayerType) {
        if enabledPrayerNotifications.contains(prayerType) {
            enabledPrayerNotifications.remove(prayerType)
        } else {
            enabledPrayerNotifications.insert(prayerType)
        }
    }
    
    func isPrayerNotificationEnabled(_ prayerType: PrayerType) -> Bool {
        return enabledPrayerNotifications.contains(prayerType)
    }
    
    func setNotificationLocation(_ location: Location) {
        notificationLocationId = location.id
        useGPSForNotifications = false
    }
    
    func useGPSLocationForNotifications() {
        useGPSForNotifications = true
        notificationLocationId = nil
    }
    
    // MARK: - Reset Methods
    
    func resetStatusBarPreferences() {
        isStatusBarWidgetEnabled = true
        statusBarDisplayFormat = .iconAndCountdown
        statusBarUpdateFrequency = .everySecond
        showStatusBarIcon = true
        statusBarClickAction = .showPopover
    }
    
    func resetNotificationPreferences() {
        notificationsEnabled = true
        enabledPrayerNotifications = Set(PrayerType.allCases.filter { $0 != .sunrise })
        notificationLocationId = nil
        useGPSForNotifications = true
        notificationAdvanceMinutes = 0
        notificationSound = "default"
    }
    
    func resetAllPreferences() {
        resetStatusBarPreferences()
        resetNotificationPreferences()
        selectedLocationId = nil
        useGPSLocation = true
    }
}

// MARK: - Status Bar Click Action

enum StatusBarClickAction: String, CaseIterable, Identifiable {
    case showPopover = "showPopover"
    case showMainWindow = "showMainWindow"
    case doNothing = "doNothing"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .showPopover:
            return "Show Prayer Times Popover"
        case .showMainWindow:
            return "Show Main Window"
        case .doNothing:
            return "Do Nothing"
        }
    }
}

// MARK: - UserDefaults Keys

private extension PreferencesManager {
    enum Keys {
        static let statusBarWidgetEnabled = "statusBarWidgetEnabled"
        static let statusBarDisplayFormat = "statusBarDisplayFormat"
        static let statusBarUpdateFrequency = "statusBarUpdateFrequency"
        static let showStatusBarIcon = "showStatusBarIcon"
        static let statusBarClickAction = "statusBarClickAction"
        static let notificationsEnabled = "notificationsEnabled"
        static let enabledPrayerNotifications = "enabledPrayerNotifications"
        static let notificationLocationId = "notificationLocationId"
        static let useGPSForNotifications = "useGPSForNotifications"
        static let notificationAdvanceMinutes = "notificationAdvanceMinutes"
        static let notificationSound = "notificationSound"
        static let selectedLocationId = "selectedLocationId"
        static let useGPSLocation = "useGPSLocation"
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let statusBarWidgetPreferenceChanged = Notification.Name("StatusBarWidgetPreferenceChanged")
    static let statusBarDisplayFormatChanged = Notification.Name("StatusBarDisplayFormatChanged")
    static let statusBarUpdateFrequencyChanged = Notification.Name("StatusBarUpdateFrequencyChanged")
    static let statusBarIconPreferenceChanged = Notification.Name("StatusBarIconPreferenceChanged")
}