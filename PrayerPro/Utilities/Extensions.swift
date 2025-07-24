//
//  Extensions.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftUI
import AppKit

// MARK: - Date Extensions
extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    var dayOfYear: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: self) ?? 1
    }
    
    func formatted(style: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Format time in user's preferred format
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: self)
    }
    
    /// Format date for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
    
    /// Check if date is in the past
    var isPast: Bool {
        self < Date()
    }
    
    /// Check if date is in the future
    var isFuture: Bool {
        self > Date()
    }
    
    /// Get time until this date
    var timeUntilDate: TimeInterval {
        self.timeIntervalSince(Date())
    }
}

// MARK: - TimeInterval Extensions
extension TimeInterval {
    var formattedCountdown: String {
        let hours = Int(self) / 3600
        let minutes = Int(self) % 3600 / 60
        let seconds = Int(self) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Format as human readable duration
    var humanReadableDuration: String {
        let hours = Int(self) / 3600
        let minutes = Int(self) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }
}

// MARK: - Color Extensions
extension Color {
    /// Prayer type specific colors
    static func prayerColor(for prayerType: PrayerType) -> Color {
        switch prayerType {
        case .fajr:
            return .purple
        case .sunrise:
            return .orange
        case .dhuhr:
            return .yellow
        case .asr:
            return .orange
        case .maghrib:
            return .red
        case .isha:
            return .indigo
        }
    }
    
    /// macOS system colors
    static let systemBackground = Color(NSColor.windowBackgroundColor)
    static let systemSecondaryBackground = Color(NSColor.controlBackgroundColor)
    static let systemTertiaryBackground = Color(NSColor.tertiarySystemFill)
}

// MARK: - View Extensions
extension View {
    /// Apply macOS-style card appearance
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color.systemSecondaryBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    /// Apply sidebar row style
    func sidebarRowStyle(isSelected: Bool = false) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
    }
    
    /// Apply prayer row style
    func prayerRowStyle(isHighlighted: Bool = false) -> some View {
        self
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.1) : Color.clear)
            )
    }
}

// MARK: - String Extensions
extension String {
    /// Truncate string to specified length
    func truncated(to length: Int) -> String {
        if self.count <= length {
            return self
        } else {
            return String(self.prefix(length)) + "..."
        }
    }
    
    /// Check if string is empty or whitespace
    var isBlank: Bool {
        self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - NSWindow Extensions
extension NSWindow {
    /// Configure window for modern macOS appearance
    func configureForModernAppearance() {
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.backgroundColor = NSColor.windowBackgroundColor
        
        if #available(macOS 11.0, *) {
            self.subtitle = ""
        }
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let toggleSidebar = Notification.Name("ToggleSidebar")
    static let refreshPrayerTimes = Notification.Name("RefreshPrayerTimes")
    static let locationSelected = Notification.Name("LocationSelected")
    static let prayerCompleted = Notification.Name("PrayerCompleted")
}

// MARK: - UserDefaults Extensions
extension UserDefaults {
    private enum Keys {
        static let selectedLocationId = "selectedLocationId"
        static let sidebarWidth = "sidebarWidth"
        static let windowFrame = "windowFrame"
        static let notificationsEnabled = "notificationsEnabled"
    }
    
    var selectedLocationId: String? {
        get { string(forKey: Keys.selectedLocationId) }
        set { set(newValue, forKey: Keys.selectedLocationId) }
    }
    
    var sidebarWidth: Double {
        get { double(forKey: Keys.sidebarWidth) }
        set { set(newValue, forKey: Keys.sidebarWidth) }
    }
    
    var notificationsEnabled: Bool {
        get { bool(forKey: Keys.notificationsEnabled) }
        set { set(newValue, forKey: Keys.notificationsEnabled) }
    }
}

// MARK: - Array Extensions
extension Array where Element == Prayer {
    /// Get prayers for today
    var todaysPrayers: [Prayer] {
        self.filter { $0.time.isToday }
    }
    
    /// Get completed prayers
    var completedPrayers: [Prayer] {
        self.filter { $0.isCompleted }
    }
    
    /// Get upcoming prayers
    var upcomingPrayers: [Prayer] {
        self.filter { $0.time.isFuture }
    }
}

extension Array where Element == Location {
    /// Sort by name
    var sortedByName: [Location] {
        self.sorted { $0.displayName < $1.displayName }
    }
}