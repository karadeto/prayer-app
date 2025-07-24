//
//  PrayerCompletionManager.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData
import CloudKit
import AppKit

@Observable
class PrayerCompletionManager {
    static let shared = PrayerCompletionManager()
    
    private let dataManager = DataManager.shared
    private var completionCache: [UUID: [PrayerCompletion]] = [:]
    
    private init() {}
    
    // MARK: - Prayer Completion Management
    
    /// Mark a prayer as completed with timestamp and visual feedback
    func markPrayerCompleted(_ prayer: Prayer, in context: ModelContext) async throws {
        do {
            // Mark prayer as completed
            try prayer.markCompleted()
            
            // Create completion record
            let completion = try PrayerCompletion(
                prayerType: prayer.prayerType,
                date: prayer.time,
                locationId: prayer.locationId
            )
            
            // Save to context
            context.insert(completion)
            try context.save()
            
            // Update cache on main thread
            await MainActor.run {
                updateCompletionCache(completion)
            }
            
            // Sync to iCloud in background
            Task {
                await syncCompletionToiCloud(completion)
            }
            
            // Post notification for UI updates on main thread
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .prayerCompletionChanged,
                    object: prayer,
                    userInfo: ["completed": true]
                )
            }
            
        } catch {
            print("Failed to mark prayer as completed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Mark a prayer as incomplete
    func markPrayerIncomplete(_ prayer: Prayer, in context: ModelContext) async throws {
        do {
            // Mark prayer as incomplete
            prayer.markIncomplete()
            
            // Remove completion record if exists
            try removeCompletionRecord(for: prayer, in: context)
            
            // Save context
            try context.save()
            
            // Update cache on main thread
            await MainActor.run {
                removeFromCompletionCache(prayer)
            }
            
            // Post notification for UI updates on main thread
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .prayerCompletionChanged,
                    object: prayer,
                    userInfo: ["completed": false]
                )
            }
            
        } catch {
            print("Failed to mark prayer as incomplete: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Toggle prayer completion status
    func togglePrayerCompletion(_ prayer: Prayer, in context: ModelContext) async throws {
        if prayer.isCompleted {
            try await markPrayerIncomplete(prayer, in: context)
        } else {
            try await markPrayerCompleted(prayer, in: context)
        }
    }
    
    // MARK: - Completion History
    
    /// Get completion status for a specific date
    func getCompletionStatus(for date: Date, locationId: UUID, in context: ModelContext) throws -> [PrayerCompletion] {
        // Check cache first
        if let cached = completionCache[locationId]?.filter({ Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            return cached
        }
        
        // Fetch from database
        let completions = try dataManager.fetchCompletionsForDate(date, in: context)
            .filter { $0.locationId == locationId }
        
        // Update cache
        for completion in completions {
            updateCompletionCache(completion)
        }
        
        return completions
    }
    
    /// Get completion history for a date range
    func getCompletionHistory(from startDate: Date, to endDate: Date, locationId: UUID, in context: ModelContext) throws -> [PrayerCompletion] {
        let calendar = Calendar.current
        let startOfStartDate = calendar.startOfDay(for: startDate)
        let endOfEndDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
        
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { completion in
                completion.locationId == locationId &&
                completion.date >= startOfStartDate &&
                completion.date < endOfEndDate
            },
            sortBy: [SortDescriptor(\.date), SortDescriptor(\.completedAt)]
        )
        
        return try context.fetch(descriptor)
    }
    
    /// Get completion statistics for a location
    func getCompletionStatistics(for locationId: UUID, in context: ModelContext) throws -> CompletionStatistics {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let completions = try getCompletionHistory(from: thirtyDaysAgo, to: Date(), locationId: locationId, in: context)
        
        let totalPrayers = completions.count
        let completedPrayers = completions.filter { _ in true }.count // All fetched are completed
        let completionRate = totalPrayers > 0 ? Double(completedPrayers) / Double(totalPrayers * 5) * 100 : 0 // 5 prayers per day
        
        // Calculate streak
        let currentStreak = calculateCurrentStreak(completions: completions)
        let longestStreak = calculateLongestStreak(completions: completions)
        
        return CompletionStatistics(
            totalPrayers: totalPrayers,
            completedPrayers: completedPrayers,
            completionRate: completionRate,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            last30Days: completions
        )
    }
    
    // MARK: - Visual Feedback Helpers
    
    /// Get visual state for a prayer completion
    func getVisualState(for prayer: Prayer) -> PrayerVisualState {
        if prayer.isCompleted {
            return .completed
        } else if prayer.time < Date() {
            return .missed
        } else {
            return .pending
        }
    }
    
    /// Get completion percentage for a date
    func getCompletionPercentage(for date: Date, locationId: UUID, in context: ModelContext) throws -> Double {
        let completions = try getCompletionStatus(for: date, locationId: locationId, in: context)
        let totalPrayers = 5 // Fajr, Dhuhr, Asr, Maghrib, Isha (excluding Sunrise)
        return Double(completions.count) / Double(totalPrayers) * 100
    }
    
    // MARK: - iCloud Sync
    
    /// Sync completion to iCloud
    private func syncCompletionToiCloud(_ completion: PrayerCompletion) async {
        do {
            // Create CloudKit record
            let record = CKRecord(recordType: "PrayerCompletion", recordID: CKRecord.ID(recordName: completion.id.uuidString))
            record["prayerType"] = completion.prayerTypeName
            record["date"] = completion.date
            record["completedAt"] = completion.completedAt
            record["locationId"] = completion.locationId.uuidString
            
            // Save to CloudKit
            let container = CKContainer.default()
            let database = container.privateCloudDatabase
            _ = try await database.save(record)
            
            // Mark as synced
            completion.markSyncedToiCloud()
            
            print("Successfully synced completion to iCloud: \(completion.prayerType.displayName)")
        } catch {
            print("Failed to sync completion to iCloud: \(error.localizedDescription)")
            // Keep local record for retry
        }
    }
    
    /// Sync all unsynced completions to iCloud
    func syncUnsyncedCompletions(in context: ModelContext) async throws {
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { $0.syncedToiCloud == false }
        )
        
        let unsyncedCompletions = try context.fetch(descriptor)
        
        for completion in unsyncedCompletions {
            await syncCompletionToiCloud(completion)
            
            // Add small delay to avoid overwhelming CloudKit
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Save context to persist sync status updates
        try context.save()
    }
    
    // MARK: - Private Helpers
    
    private func removeCompletionRecord(for prayer: Prayer, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { completion in
                completion.prayerTypeName == prayer.name &&
                completion.locationId == prayer.locationId
            }
        )
        
        let completions = try context.fetch(descriptor)
        for completion in completions.filter({ Calendar.current.isDate($0.date, inSameDayAs: prayer.time) }) {
            context.delete(completion)
        }
    }
    
    private func updateCompletionCache(_ completion: PrayerCompletion) {
        if completionCache[completion.locationId] == nil {
            completionCache[completion.locationId] = []
        }
        
        // Remove existing completion for same prayer/date if exists
        completionCache[completion.locationId]?.removeAll { existing in
            existing.prayerType == completion.prayerType &&
            Calendar.current.isDate(existing.date, inSameDayAs: completion.date)
        }
        
        // Add new completion
        completionCache[completion.locationId]?.append(completion)
    }
    
    private func removeFromCompletionCache(_ prayer: Prayer) {
        completionCache[prayer.locationId]?.removeAll { completion in
            completion.prayerType == prayer.prayerType &&
            Calendar.current.isDate(completion.date, inSameDayAs: prayer.time)
        }
    }
    
    private func calculateCurrentStreak(completions: [PrayerCompletion]) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var currentDate = Date()
        
        // Go backwards from today
        while true {
            let dayCompletions = completions.filter { calendar.isDate($0.date, inSameDayAs: currentDate) }
            let uniquePrayerTypes = Set(dayCompletions.map { $0.prayerType })
            
            if uniquePrayerTypes.count >= 5 { // All 5 prayers completed
                streak += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
            } else {
                break
            }
        }
        
        return streak
    }
    
    private func calculateLongestStreak(completions: [PrayerCompletion]) -> Int {
        let calendar = Calendar.current
        let sortedCompletions = completions.sorted { $0.date < $1.date }
        
        var longestStreak = 0
        var currentStreak = 0
        var lastDate: Date?
        
        // Group by date and check consecutive days
        let groupedByDate = Dictionary(grouping: sortedCompletions) { completion in
            calendar.startOfDay(for: completion.date)
        }
        
        let sortedDates = groupedByDate.keys.sorted()
        
        for date in sortedDates {
            let dayCompletions = groupedByDate[date] ?? []
            let uniquePrayerTypes = Set(dayCompletions.map { $0.prayerType })
            
            if uniquePrayerTypes.count >= 5 { // All 5 prayers completed
                if let lastDate = lastDate,
                   calendar.dateInterval(of: .day, for: lastDate)?.end == calendar.dateInterval(of: .day, for: date)?.start {
                    currentStreak += 1
                } else {
                    currentStreak = 1
                }
                longestStreak = max(longestStreak, currentStreak)
            } else {
                currentStreak = 0
            }
            
            lastDate = date
        }
        
        return longestStreak
    }
}

// MARK: - Supporting Types

enum PrayerVisualState {
    case pending
    case completed
    case missed
    
    var color: NSColor {
        switch self {
        case .pending:
            return .systemBlue
        case .completed:
            return .systemGreen
        case .missed:
            return .systemOrange
        }
    }
    
    var iconName: String {
        switch self {
        case .pending:
            return "circle"
        case .completed:
            return "checkmark.circle.fill"
        case .missed:
            return "exclamationmark.circle"
        }
    }
}

struct CompletionStatistics {
    let totalPrayers: Int
    let completedPrayers: Int
    let completionRate: Double
    let currentStreak: Int
    let longestStreak: Int
    let last30Days: [PrayerCompletion]
}

// MARK: - Notification Names

extension Notification.Name {
    static let prayerCompletionChanged = Notification.Name("prayerCompletionChanged")
}