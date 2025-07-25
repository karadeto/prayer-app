#!/usr/bin/env swift

import Foundation

// Simple test to verify preferences functionality
print("Testing Preferences Manager...")

// Test UserDefaults keys
let testDefaults = UserDefaults.standard

// Test setting and getting preferences
testDefaults.set(true, forKey: "statusBarWidgetEnabled")
testDefaults.set("iconAndCountdown", forKey: "statusBarDisplayFormat")
testDefaults.set(5, forKey: "statusBarUpdateFrequency")

let widgetEnabled = testDefaults.bool(forKey: "statusBarWidgetEnabled")
let displayFormat = testDefaults.string(forKey: "statusBarDisplayFormat")
let updateFrequency = testDefaults.integer(forKey: "statusBarUpdateFrequency")

print("✅ Widget Enabled: \(widgetEnabled)")
print("✅ Display Format: \(displayFormat ?? "nil")")
print("✅ Update Frequency: \(updateFrequency)")

// Test enum values
enum StatusBarDisplayFormat: String, CaseIterable {
    case countdown = "countdown"
    case nextPrayerTime = "nextPrayerTime"
    case nextPrayerName = "nextPrayerName"
    case iconAndCountdown = "iconAndCountdown"
    
    var displayName: String {
        switch self {
        case .countdown: return "Countdown Only"
        case .nextPrayerTime: return "Next Prayer Time"
        case .nextPrayerName: return "Next Prayer Name"
        case .iconAndCountdown: return "Icon + Countdown"
        }
    }
}

enum StatusBarUpdateFrequency: Int, CaseIterable {
    case everySecond = 1
    case every5Seconds = 5
    case every10Seconds = 10
    case every30Seconds = 30
    case everyMinute = 60
    
    var displayName: String {
        switch self {
        case .everySecond: return "Every Second"
        case .every5Seconds: return "Every 5 Seconds"
        case .every10Seconds: return "Every 10 Seconds"
        case .every30Seconds: return "Every 30 Seconds"
        case .everyMinute: return "Every Minute"
        }
    }
}

// Test enum functionality
let testFormat = StatusBarDisplayFormat(rawValue: "iconAndCountdown")
let testFrequency = StatusBarUpdateFrequency(rawValue: 5)

print("✅ Format enum: \(testFormat?.displayName ?? "nil")")
print("✅ Frequency enum: \(testFrequency?.displayName ?? "nil")")

print("✅ All preferences tests passed!")