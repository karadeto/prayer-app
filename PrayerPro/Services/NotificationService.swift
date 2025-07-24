//
//  NotificationService.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import UserNotifications

@Observable
class NotificationService {
    static let shared = NotificationService()
    
    private init() {}
    
    // MARK: - Permission Management
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }
    
    // MARK: - Notification Scheduling
    func schedulePrayerNotifications(for prayers: [Prayer]) async {
        // Remove existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        for prayer in prayers {
            await scheduleNotification(for: prayer)
        }
    }
    
    private func scheduleNotification(for prayer: Prayer) async {
        let content = UNMutableNotificationContent()
        content.title = "Prayer Time"
        content.body = "It's time for \(prayer.prayerType.displayName) prayer"
        content.sound = .default
        
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: prayer.time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: prayer.id.uuidString,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }
}