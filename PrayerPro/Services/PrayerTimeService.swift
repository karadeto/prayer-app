//
//  PrayerTimeService.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData

@Observable
class PrayerTimeService {
    static let shared = PrayerTimeService()
    
    private let apiClient = DiyanetAPIClient.shared
    private let cacheManager = CacheManager.shared
    private var cachedPrayers: [Prayer] = []
    private var lastFetchDate: Date?
    private var lastFetchLocation: Location?
    
    private init() {}
    
    // MARK: - Prayer Time Management
    
    /// Fetch daily prayer times for a location (GPS locations use daily data only)
    func fetchDailyPrayerTimes(for location: Location, in context: ModelContext) async throws -> [Prayer] {
        let today = Date()
        
        // Check cache first
        if let cachedPrayers = try cacheManager.getCachedDailyPrayers(for: location.id, date: today, in: context) {
            print("Using cached daily prayer times for \(location.displayName)")
            self.cachedPrayers = cachedPrayers
            self.lastFetchDate = today
            self.lastFetchLocation = location
            return cachedPrayers
        }
        
        // Fetch from API if not cached or expired
        guard let diyanetId = location.diyanetId else {
            throw DiyanetAPIError.invalidURL
        }
        
        do {
            let response = try await apiClient.fetchDailyPrayerTimes(
                locationId: diyanetId,
                date: today,
                method: "diyanet"
            )
            
            // Convert response to Prayer objects
            let prayers = try convertDailyResponseToPrayers(response, location: location)
            
            // Cache the results
            try cacheManager.cacheDailyPrayers(prayers, for: location.id, date: today, in: context)
            
            // Update in-memory cache
            cachedPrayers = prayers
            lastFetchDate = today
            lastFetchLocation = location
            
            print("Fetched and cached daily prayer times for \(location.displayName)")
            return prayers
        } catch {
            print("Failed to fetch daily prayer times: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Fetch annual prayer times for a location (favorites use annual data for offline access)
    func fetchAnnualPrayerTimes(for location: Location, in context: ModelContext) async throws -> [Prayer] {
        let currentYear = Calendar.current.component(.year, from: Date())
        
        // Check cache first
        if let cachedPrayers = try cacheManager.getCachedAnnualPrayers(for: location.id, year: currentYear, in: context) {
            print("Using cached annual prayer times for \(location.displayName)")
            return cachedPrayers
        }
        
        // Fetch from API if not cached or expired
        guard let diyanetId = location.diyanetId else {
            throw DiyanetAPIError.invalidURL
        }
        
        do {
            let response = try await apiClient.fetchAnnualPrayerTimes(
                locationId: diyanetId,
                year: currentYear
            )
            
            // Convert response to Prayer objects
            let prayers = try convertAnnualResponseToPrayers(response, location: location)
            
            // Cache the results
            try cacheManager.cacheAnnualPrayers(prayers, for: location.id, year: currentYear, in: context)
            
            print("Fetched and cached annual prayer times for \(location.displayName)")
            return prayers
        } catch {
            print("Failed to fetch annual prayer times: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Get prayer times for a location with smart caching strategy
    func getPrayerTimes(for location: Location, in context: ModelContext) async throws -> [Prayer] {
        if location.isGPSLocation {
            // GPS locations: fetch daily data only
            return try await fetchDailyPrayerTimes(for: location, in: context)
        } else if location.isFavorite {
            // Favorite locations: try annual data first, fallback to daily
            let currentYear = Calendar.current.component(.year, from: Date())
            
            if try cacheManager.hasCachedAnnualPrayers(for: location.id, year: currentYear, in: context) {
                let annualPrayers = try await fetchAnnualPrayerTimes(for: location, in: context)
                return getTodaysPrayers(from: annualPrayers)
            } else {
                // Fetch annual data in background for future use
                Task {
                    do {
                        _ = try await fetchAnnualPrayerTimes(for: location, in: context)
                    } catch {
                        print("Background annual fetch failed: \(error.localizedDescription)")
                    }
                }
                
                // Return daily data for immediate use
                return try await fetchDailyPrayerTimes(for: location, in: context)
            }
        } else {
            // Regular locations: use daily data
            return try await fetchDailyPrayerTimes(for: location, in: context)
        }
    }
    
    /// Get current prayer status with next prayer information
    func getCurrentPrayerStatus(for location: Location? = nil, in context: ModelContext? = nil) async -> PrayerStatus {
        let now = Date()
        var todaysPrayers: [Prayer] = []
        
        // Try to get today's prayers from various sources
        if let location = location, let context = context {
            do {
                todaysPrayers = try await getPrayerTimes(for: location, in: context)
            } catch {
                print("Failed to get prayer times for status: \(error.localizedDescription)")
                todaysPrayers = getTodaysPrayers(from: cachedPrayers)
            }
        } else {
            todaysPrayers = getTodaysPrayers(from: cachedPrayers)
        }
        
        guard !todaysPrayers.isEmpty else {
            return PrayerStatus(currentPrayer: nil, nextPrayer: nil, timeUntilNext: 0, allPrayers: [])
        }
        
        let sortedPrayers = todaysPrayers.sorted { $0.time < $1.time }
        
        // Find current and next prayer with improved logic
        let (currentPrayer, nextPrayer) = findCurrentAndNextPrayer(from: sortedPrayers, at: now)
        
        let timeUntilNext = nextPrayer?.time.timeIntervalSince(now) ?? 0
        
        return PrayerStatus(
            currentPrayer: currentPrayer,
            nextPrayer: nextPrayer,
            timeUntilNext: max(0, timeUntilNext),
            allPrayers: sortedPrayers
        )
    }
    
    /// Get the next upcoming prayer
    func getNextPrayer(for location: Location? = nil, in context: ModelContext? = nil) async -> Prayer? {
        let status = await getCurrentPrayerStatus(for: location, in: context)
        return status.nextPrayer
    }
    
    /// Get time remaining until next prayer in seconds
    func getTimeUntilNextPrayer(for location: Location? = nil, in context: ModelContext? = nil) async -> TimeInterval {
        let status = await getCurrentPrayerStatus(for: location, in: context)
        return status.timeUntilNext
    }
    
    /// Get prayers for today from a given array
    func getTodaysPrayers(from prayers: [Prayer], date: Date = Date()) -> [Prayer] {
        return prayers.filter { prayer in
            Calendar.current.isDate(prayer.time, inSameDayAs: date)
        }
    }
    
    /// Get prayers for a specific date from cached annual data
    func getPrayersForDate(_ date: Date, location: Location, in context: ModelContext) async throws -> [Prayer] {
        let currentYear = Calendar.current.component(.year, from: date)
        
        // Try to get from annual cache first
        if let annualPrayers = try cacheManager.getCachedAnnualPrayers(for: location.id, year: currentYear, in: context) {
            return getTodaysPrayers(from: annualPrayers, date: date)
        }
        
        // Fallback to daily fetch if annual not available
        if Calendar.current.isDate(date, inSameDayAs: Date()) {
            return try await fetchDailyPrayerTimes(for: location, in: context)
        }
        
        // For historical dates, we need annual data
        let annualPrayers = try await fetchAnnualPrayerTimes(for: location, in: context)
        return getTodaysPrayers(from: annualPrayers, date: date)
    }
    
    // MARK: - Prayer Time Calculations
    
    /// Find current and next prayer from sorted prayer list
    private func findCurrentAndNextPrayer(from sortedPrayers: [Prayer], at currentTime: Date) -> (current: Prayer?, next: Prayer?) {
        var currentPrayer: Prayer?
        var nextPrayer: Prayer?
        
        // Filter out sunrise as it's not a prayer time for notifications
        let prayerTimes = sortedPrayers.filter { $0.prayerType != .sunrise }
        
        for (_, prayer) in prayerTimes.enumerated() {
            if prayer.time <= currentTime {
                currentPrayer = prayer
            } else {
                nextPrayer = prayer
                break
            }
        }
        
        // If no next prayer found for today, next would be Fajr of tomorrow
        // For now, we'll leave it as nil - this could be enhanced to fetch tomorrow's Fajr
        
        return (currentPrayer, nextPrayer)
    }
    
    /// Calculate time remaining in a human-readable format
    func formatTimeRemaining(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        let seconds = Int(timeInterval) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Get prayer time in user-friendly format
    func formatPrayerTime(_ prayer: Prayer) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: prayer.time)
    }
    
    /// Check if a prayer time has passed
    func hasPrayerTimePassed(_ prayer: Prayer, at currentTime: Date = Date()) -> Bool {
        return prayer.time < currentTime
    }
    
    /// Get the current active prayer period
    func getCurrentPrayerPeriod(from prayers: [Prayer], at currentTime: Date = Date()) -> (current: Prayer?, next: Prayer?) {
        let sortedPrayers = prayers.sorted { $0.time < $1.time }
        return findCurrentAndNextPrayer(from: sortedPrayers, at: currentTime)
    }
    
    // MARK: - Cache Management
    
    /// Clear all cached prayer data
    func clearAllCache(in context: ModelContext) throws {
        try cacheManager.performCleanup(in: context)
        cachedPrayers.removeAll()
        lastFetchDate = nil
        lastFetchLocation = nil
    }
    
    /// Get cache statistics
    func getCacheStatistics(in context: ModelContext) throws -> CacheStatistics {
        return try cacheManager.getCacheStatistics(in: context)
    }
    
    /// Check if cached data is still valid (within the same day and location)
    func isCacheValid(for location: Location) -> Bool {
        guard let lastFetchDate = lastFetchDate,
              let lastFetchLocation = lastFetchLocation else {
            return false
        }
        
        // Check if it's the same day and same location
        let isSameDay = Calendar.current.isDate(lastFetchDate, inSameDayAs: Date())
        let isSameLocation = lastFetchLocation.id == location.id
        
        return isSameDay && isSameLocation && !cachedPrayers.isEmpty
    }
    
    // MARK: - Helper Methods
    
    private func convertDailyResponseToPrayers(_ response: DailyPrayerScheduleResponse, location: Location) throws -> [Prayer] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.date(from: response.date) != nil else {
            throw DiyanetAPIError.invalidDateFormat
        }
        
        var prayers: [Prayer] = []
        
        for prayerResponse in response.prayers {
            guard let prayerType = PrayerType(rawValue: prayerResponse.type) else {
                continue // Skip unknown prayer types
            }
            
            guard let prayerTime = {
                // Strip timezone info and parse as local time
                let cleanTime = prayerResponse.time.replacingOccurrences(of: "Z$", with: "", options: .regularExpression)
                                                   .replacingOccurrences(of: "[+-]\\d{2}:\\d{2}$", with: "", options: .regularExpression)
                
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                
                // Try with milliseconds first
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
                if let date = formatter.date(from: cleanTime) {
                    return date
                }
                
                // Try without milliseconds
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                return formatter.date(from: cleanTime)
            }() else {
                continue // Skip prayers with invalid time format
            }
            
            let prayer = try Prayer(
                prayerType: prayerType,
                time: prayerTime,
                locationId: location.id,
                isCompleted: prayerResponse.completed ?? false
            )
            
            prayers.append(prayer)
        }
        
        return prayers.sorted { $0.time < $1.time }
    }
    
    private func convertAnnualResponseToPrayers(_ response: AnnualPrayerDataResponse, location: Location) throws -> [Prayer] {
        var allPrayers: [Prayer] = []
        
        for schedule in response.schedules {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard formatter.date(from: schedule.date) != nil else {
                continue // Skip schedules with invalid dates
            }
            
            for prayerResponse in schedule.prayers {
                guard let prayerType = PrayerType(rawValue: prayerResponse.type) else {
                    continue // Skip unknown prayer types
                }
                
                guard let prayerTime = {
                    // Strip timezone info and parse as local time
                    let cleanTime = prayerResponse.time.replacingOccurrences(of: "Z$", with: "", options: .regularExpression)
                                                       .replacingOccurrences(of: "[+-]\\d{2}:\\d{2}$", with: "", options: .regularExpression)
                    
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    
                    // Try with milliseconds first
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
                    if let date = formatter.date(from: cleanTime) {
                        return date
                    }
                    
                    // Try without milliseconds
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    return formatter.date(from: cleanTime)
                }() else {
                    continue // Skip prayers with invalid time format
                }
                
                let prayer = try Prayer(
                    prayerType: prayerType,
                    time: prayerTime,
                    locationId: location.id,
                    isCompleted: prayerResponse.completed ?? false
                )
                
                allPrayers.append(prayer)
            }
        }
        
        return allPrayers.sorted { $0.time < $1.time }
    }
    
    // MARK: - Background Operations
    
    /// Preload annual data for favorite locations in background
    func preloadAnnualDataForFavorites(_ locations: [Location], in context: ModelContext) {
        Task {
            let currentYear = Calendar.current.component(.year, from: Date())
            
            for location in locations.filter({ $0.isFavorite }) {
                do {
                    // Check if we already have cached data
                    if try !cacheManager.hasCachedAnnualPrayers(for: location.id, year: currentYear, in: context) {
                        print("Preloading annual data for \(location.displayName)")
                        _ = try await fetchAnnualPrayerTimes(for: location, in: context)
                        
                        // Add small delay to avoid overwhelming the API
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    }
                } catch {
                    print("Failed to preload annual data for \(location.displayName): \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Refresh stale cache entries in background
    func refreshStaleCacheEntries(in context: ModelContext) {
        Task {
            do {
                try cacheManager.performCleanup(in: context)
            } catch {
                print("Failed to refresh stale cache entries: \(error.localizedDescription)")
            }
        }
    }
}