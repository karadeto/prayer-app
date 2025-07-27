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
            // Check if this prayer type is already completed today (across all locations)
            // Use prayer.time directly to avoid timezone issues with startOfDay
            let existingCompletions = try getCompletionStatus(for: prayer.time, locationId: prayer.locationId, in: context)
            
            // Check if this prayer type is already completed today
            let alreadyCompleted = existingCompletions.contains { completion in
                completion.prayerType == prayer.prayerType &&
                Calendar.current.isDate(completion.date, inSameDayAs: prayer.time)
            }
            
            if alreadyCompleted {
                print("Prayer \(prayer.prayerType.displayName) already completed today")
                // Still mark this prayer instance as completed for UI consistency
                try prayer.markCompleted()
                try context.save()
                
                // Post notification for UI updates
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .prayerCompletionChanged,
                        object: prayer,
                        userInfo: ["completed": true]
                    )
                }
                return
            }
            
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
            
            // Sync to iCloud in background with fallback
            Task {
                await syncCompletionToiCloudWithFallback(completion, in: context)
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
    
    /// Get completion status for a specific date (location-independent for daily completions)
    func getCompletionStatus(for date: Date, locationId: UUID, in context: ModelContext) throws -> [PrayerCompletion] {
        // SwiftData ModelContext doesn't have isInvalidated like Core Data
        // We'll handle any context issues through error handling
        
        // Check cache first with safety - search across all locations for daily completions
        var dailyCompletions: [PrayerCompletion] = []
        
        // Search cache across all locations for this date
        for (_, cached) in completionCache {
            let filteredCache = cached.compactMap { completion -> PrayerCompletion? in
                // Basic safety check before accessing properties
                guard completion.id.uuidString.count == 36,
                      !completion.prayerTypeName.isEmpty else {
                    print("Warning: Invalid completion in cache (basic properties)")
                    return nil
                }
                
                do {
                    // Validate completion is still valid
                    try completion.validate()
                    if Calendar.current.isDate(completion.date, inSameDayAs: date) {
                        return completion
                    }
                } catch {
                    print("Warning: Invalid completion in cache, removing: \(error)")
                    // Remove invalid completion from cache
                    Task { @MainActor in
                        removeInvalidCompletionFromCache(completion, locationId: completion.locationId)
                    }
                }
                return nil
            }
            dailyCompletions.append(contentsOf: filteredCache)
        }
        
        if !dailyCompletions.isEmpty {
            return dailyCompletions
        }
        
        // Fetch from database with error handling - search all locations for daily completions
        do {
            let completions = try dataManager.fetchCompletionsForDate(date, in: context)
            // Don't filter by locationId - prayers completed are location-independent for the day
            
            // Safely update cache
            for completion in completions {
                do {
                    try completion.validate()
                    updateCompletionCache(completion)
                } catch {
                    print("Warning: Skipping invalid completion from database: \(error)")
                }
            }
            
            return completions
        } catch {
            print("Error in getCompletionStatus: \(error)")
            throw error
        }
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
    func getVisualState(for prayer: Prayer, nextPrayer: Prayer? = nil, allPrayers: [Prayer] = []) -> PrayerVisualState {
        let now = Date()
        
        // Sunrise is not a prayer time, so it should never be marked as missed
        if prayer.prayerType == .sunrise {
            return .pending
        }
        
        if prayer.isCompleted {
            return .completed
        }
        
        // For missed logic, we need to find the next TIME MARKER (including sunrise) after this prayer
        if !allPrayers.isEmpty {
            // Sort all prayers by time
            let sortedPrayers = allPrayers.sorted { $0.time < $1.time }
            
            // Find the next time marker after this prayer
            var nextTimeMarker: Prayer?
            for timeMarker in sortedPrayers {
                if timeMarker.time > prayer.time {
                    nextTimeMarker = timeMarker
                    break
                }
            }
            
            // Prayer is missed when current time >= next time marker
            if let nextTimeMarker = nextTimeMarker {
                if now >= nextTimeMarker.time {
                    return .missed
                } else {
                    return .pending
                }
            }
        }
        
        // Fallback to original logic if allPrayers not provided
        if let nextPrayer = nextPrayer {
            // Prayer is missed when current time >= next prayer time
            if now >= nextPrayer.time {
                return .missed
            } else {
                return .pending
            }
        } else {
            // Special handling for last prayer (Isha) when there's no next prayer today
            if prayer.prayerType == .isha && prayer.time < now {
                // For Isha, consider it missed only after midnight (start of next day)
                let calendar = Calendar.current
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: prayer.time),
                   let startOfNextDay = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: nextDay),
                   now >= startOfNextDay {
                    return .missed
                } else {
                    return .pending
                }
            } else if prayer.time < now {
                // For other prayers without next prayer info, use old logic
                return .missed
            } else {
                return .pending
            }
        }
    }
    
    /// Get completion percentage for a date (location-independent)
    func getCompletionPercentage(for date: Date, locationId: UUID, in context: ModelContext) throws -> Double {
        let completions = try getCompletionStatus(for: date, locationId: locationId, in: context)
        let totalPrayers = 5 // Fajr, Dhuhr, Asr, Maghrib, Isha (excluding Sunrise)
        
        // Get unique prayer types completed (remove duplicates across locations)
        let uniquePrayerTypes = Set(completions.map { $0.prayerType })
        return Double(uniquePrayerTypes.count) / Double(totalPrayers) * 100
    }
    
    // MARK: - iCloud Sync
    
    /// Sync completion to iCloud using the dedicated sync service
    private func syncCompletionToiCloud(_ completion: PrayerCompletion) async {
        do {
            try await iCloudSyncService.shared.syncCompletionToiCloud(completion)
        } catch {
            print("Failed to sync completion to iCloud: \(error.localizedDescription)")
            // Keep local record for retry
        }
    }
    
    /// Sync completion to iCloud with fallback to local storage
    private func syncCompletionToiCloudWithFallback(_ completion: PrayerCompletion, in context: ModelContext) async {
        do {
            // First verify iCloud availability
            try await iCloudSyncService.shared.verifyiCloudAvailability()
            
            // Attempt to sync to iCloud
            try await iCloudSyncService.shared.syncCompletionToiCloud(completion)
            
            print("Successfully synced completion to iCloud: \(completion.prayerType.displayName)")
            
        } catch {
            print("iCloud sync failed, falling back to local storage: \(error.localizedDescription)")
            
            // Fallback: ensure completion is saved locally and marked for retry
            completion.markNotSynced()
            
            do {
                try context.save()
                
                // Schedule retry after delay
                Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    await retryiCloudSync(completion, in: context)
                }
                
            } catch {
                print("Failed to save completion locally: \(error.localizedDescription)")
            }
        }
    }
    
    /// Retry iCloud sync with exponential backoff
    private func retryiCloudSync(_ completion: PrayerCompletion, in context: ModelContext, attempt: Int = 1) async {
        let maxAttempts = 3
        
        guard attempt <= maxAttempts else {
            print("Max retry attempts reached for completion: \(completion.prayerType.displayName)")
            return
        }
        
        do {
            try await iCloudSyncService.shared.syncCompletionToiCloud(completion)
            
            // Success - save the updated sync status
            try context.save()
            print("Retry successful for completion: \(completion.prayerType.displayName)")
            
        } catch {
            print("Retry attempt \(attempt) failed: \(error.localizedDescription)")
            
            if attempt < maxAttempts {
                // Exponential backoff: 10s, 30s, 90s
                let delay = TimeInterval(10 * Int(pow(3.0, Double(attempt - 1))))
                
                Task {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await retryiCloudSync(completion, in: context, attempt: attempt + 1)
                }
            }
        }
    }
    
    /// Sync all unsynced completions to iCloud
    func syncUnsyncedCompletions(in context: ModelContext) async throws {
        try await iCloudSyncService.shared.syncAllUnsyncedCompletions(in: context)
    }
    
    /// Perform full sync from iCloud (download remote completions)
    func performFullSyncFromiCloud(in context: ModelContext) async throws {
        try await iCloudSyncService.shared.syncCompletionsFromiCloud(in: context)
    }
    
    /// Restore completion states for all prayers in the context on app startup
    func restoreAllCompletionStates(in context: ModelContext) async throws {
        print("🔄 Restoring completion states for all prayers...")
        
        // Calculate date boundaries outside the predicate
        let calendar = Calendar.current
        let today = Date()
        let startOfToday = calendar.startOfDay(for: today)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        
        // Fetch all prayers from the current day using computed dates
        let descriptor = FetchDescriptor<Prayer>(
            predicate: #Predicate<Prayer> { prayer in
                prayer.time >= startOfToday &&
                prayer.time < startOfTomorrow
            }
        )
        
        let allPrayers = try context.fetch(descriptor)
        print("📊 Found \(allPrayers.count) prayers for today")
        
        // Get all completions for today (location-independent)
        // Use start of day to ensure proper date matching
        let todayCompletions = try getCompletionStatus(for: startOfToday, locationId: UUID(), in: context)
        print("📊 Found \(todayCompletions.count) completions for today")
        
        if !todayCompletions.isEmpty {
            print("📋 Today's completions:")
            for completion in todayCompletions {
                print("   - \(completion.prayerType.displayName) completed at \(completion.completedAt)")
            }
        }
        
        var restoredCount = 0
        var clearedCount = 0
        
        for prayer in allPrayers {
            // Find matching completion record for this prayer type
            if let completion = todayCompletions.first(where: { $0.prayerType == prayer.prayerType }) {
                if !prayer.isCompleted {
                    prayer.isCompleted = true
                    prayer.completedAt = completion.completedAt
                    restoredCount += 1
                    print("✅ Restored completion state for \(prayer.name) (\(prayer.prayerType.displayName))")
                } else {
                    print("ℹ️ Prayer \(prayer.name) already marked as completed")
                }
            } else {
                if prayer.isCompleted {
                    prayer.isCompleted = false
                    prayer.completedAt = nil
                    clearedCount += 1
                    print("🔄 Cleared outdated completion state for \(prayer.name)")
                }
            }
        }
        
        if restoredCount > 0 || clearedCount > 0 {
            try context.save()
            print("✅ Restored completion states for \(restoredCount) prayers, cleared \(clearedCount) outdated states")
        } else {
            print("ℹ️ No completion states needed restoration")
        }
    }
    
    /// Check iCloud sync status
    func getiCloudSyncStatus() -> (isSyncing: Bool, lastSync: Date?, error: Error?) {
        let syncService = iCloudSyncService.shared
        return (syncService.isSyncing, syncService.lastSyncDate, syncService.syncError)
    }
    
    /// Manual method to force sync and restore completion states (for debugging)
    func forceSyncAndRestore(in context: ModelContext) async throws {
        print("🔧 Manual force sync and restore initiated...")
        
        // First sync from iCloud
        try await iCloudSyncService.shared.syncCompletionsFromiCloud(in: context)
        
        // Then restore completion states
        try await restoreAllCompletionStates(in: context)
        
        print("✅ Manual force sync and restore completed")
    }
    
    // MARK: - Private Helpers
    
    private func removeCompletionRecord(for prayer: Prayer, in context: ModelContext) throws {
        // Remove completion records for this prayer type on this date (across all locations)
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { completion in
                completion.prayerTypeName == prayer.name
            }
        )
        
        let completions = try context.fetch(descriptor)
        for completion in completions.filter({ Calendar.current.isDate($0.date, inSameDayAs: prayer.time) }) {
            // Remove from cache first
            removeInvalidCompletionFromCache(completion, locationId: completion.locationId)
            context.delete(completion)
        }
    }
    
    private func updateCompletionCache(_ completion: PrayerCompletion) {
        guard !completion.id.uuidString.isEmpty else {
            print("Warning: Attempted to cache completion with invalid ID")
            return
        }
        
        if completionCache[completion.locationId] == nil {
            completionCache[completion.locationId] = []
        }
        
        // Safely remove existing completion for same prayer/date if exists
        completionCache[completion.locationId]?.removeAll { existing in
            do {
                return existing.prayerType == completion.prayerType &&
                       Calendar.current.isDate(existing.date, inSameDayAs: completion.date)
            } catch {
                print("Warning: Error comparing completion dates, removing from cache: \(error)")
                return true // Remove problematic entries
            }
        }
        
        // Add new completion
        completionCache[completion.locationId]?.append(completion)
    }
    
    private func removeInvalidCompletionFromCache(_ completion: PrayerCompletion, locationId: UUID) {
        completionCache[locationId]?.removeAll { $0.id == completion.id }
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