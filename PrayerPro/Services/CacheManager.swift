//
//  CacheManager.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData

// MARK: - Cache Configuration

struct CacheConfiguration {
    let maxDailyEntries: Int
    let maxAnnualEntries: Int
    let dailyCacheExpiryHours: Int
    let annualCacheExpiryDays: Int
    let cleanupIntervalHours: Int
    
    static let `default` = CacheConfiguration(
        maxDailyEntries: 100,
        maxAnnualEntries: 10,
        dailyCacheExpiryHours: 24,
        annualCacheExpiryDays: 30,
        cleanupIntervalHours: 24
    )
}

// MARK: - Cache Entry Models

@Model
final class DailyCacheEntry {
    @Attribute(.unique) var id: UUID
    var locationId: UUID
    var date: Date
    var prayersData: Data // Serialized [Prayer] array
    var createdAt: Date
    var lastAccessedAt: Date
    var expiresAt: Date
    
    init(locationId: UUID, date: Date, prayers: [Prayer], expiryHours: Int = 24) throws {
        self.id = UUID()
        self.locationId = locationId
        self.date = Calendar.current.startOfDay(for: date)
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.expiresAt = Date().addingTimeInterval(TimeInterval(expiryHours * 3600))
        
        // Serialize prayers to data
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.prayersData = try encoder.encode(prayers)
    }
    
    func getPrayers() throws -> [Prayer] {
        self.lastAccessedAt = Date()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Prayer].self, from: prayersData)
    }
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    var isStale: Bool {
        // Consider stale if older than 6 hours
        return Date().timeIntervalSince(createdAt) > 6 * 3600
    }
}

@Model
final class AnnualCacheEntry {
    @Attribute(.unique) var id: UUID
    var locationId: UUID
    var year: Int
    var prayersData: Data // Serialized [Prayer] array
    var createdAt: Date
    var lastAccessedAt: Date
    var expiresAt: Date
    var dataSize: Int // Size in bytes for cleanup decisions
    
    init(locationId: UUID, year: Int, prayers: [Prayer], expiryDays: Int = 30) throws {
        self.id = UUID()
        self.locationId = locationId
        self.year = year
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.expiresAt = Date().addingTimeInterval(TimeInterval(expiryDays * 24 * 3600))
        
        // Serialize prayers to data
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(prayers)
        self.prayersData = encodedData
        self.dataSize = encodedData.count
    }
    
    func getPrayers() throws -> [Prayer] {
        self.lastAccessedAt = Date()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Prayer].self, from: prayersData)
    }
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    var isStale: Bool {
        // Consider stale if older than 7 days
        return Date().timeIntervalSince(createdAt) > 7 * 24 * 3600
    }
}

// MARK: - Cache Manager

@Observable
class CacheManager {
    static let shared = CacheManager()
    
    private let config: CacheConfiguration
    private var lastCleanupTime: Date?
    
    private init(config: CacheConfiguration = .default) {
        self.config = config
        schedulePeriodicCleanup()
    }
    
    // MARK: - Daily Cache Operations
    
    /// Cache daily prayer times for a location
    func cacheDailyPrayers(_ prayers: [Prayer], for locationId: UUID, date: Date, in context: ModelContext) throws {
        // Validate input parameters
        guard !prayers.isEmpty else {
            print("CacheManager: Skipping cache - no prayers to cache")
            return
        }
        
        // Validate all prayers before caching
        do {
            try prayers.validateAll()
        } catch {
            print("CacheManager: Invalid prayers data, skipping cache: \(error)")
            throw CacheError.serializationFailed(error)
        }
        
        // Perform operations with proper error handling
        do {
            // Remove existing entry for same location and date with error handling
            try removeDailyCacheEntry(for: locationId, date: date, in: context)
            
            // Force save after deletion to avoid hash table conflicts
            try context.save()
            
            // Create new cache entry with validation
            let entry = try DailyCacheEntry(
                locationId: locationId,
                date: date,
                prayers: prayers,
                expiryHours: config.dailyCacheExpiryHours
            )
            
            // Insert and save immediately
            context.insert(entry)
            try context.save()
            
            print("CacheManager: Successfully cached \(prayers.count) prayers for location \(locationId)")
            
            // Cleanup if needed (with separate error handling)
            do {
                try cleanupDailyCacheIfNeeded(in: context)
            } catch {
                print("CacheManager: Cleanup failed but cache operation succeeded: \(error)")
                // Don't throw - cache operation was successful
            }
            
        } catch {
            print("CacheManager: Failed to cache daily prayers: \(error)")
            throw CacheError.serializationFailed(error)
        }
    }
    
    /// Retrieve cached daily prayer times
    func getCachedDailyPrayers(for locationId: UUID, date: Date, in context: ModelContext) throws -> [Prayer]? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        
        let descriptor = FetchDescriptor<DailyCacheEntry>(
            predicate: #Predicate { entry in
                entry.locationId == locationId && entry.date == startOfDay
            }
        )
        
        guard let entry = try context.fetch(descriptor).first else {
            return nil
        }
        
        // Check if expired
        if entry.isExpired {
            context.delete(entry)
            try context.save()
            return nil
        }
        
        return try entry.getPrayers()
    }
    
    /// Check if daily cache exists and is valid
    func hasCachedDailyPrayers(for locationId: UUID, date: Date, in context: ModelContext) throws -> Bool {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let now = Date()
        
        let descriptor = FetchDescriptor<DailyCacheEntry>(
            predicate: #Predicate { entry in
                entry.locationId == locationId && entry.date == startOfDay && entry.expiresAt > now
            }
        )
        
        let results = try context.fetch(descriptor)
        return !results.isEmpty
    }
    
    // MARK: - Annual Cache Operations
    
    /// Cache annual prayer times for a location
    func cacheAnnualPrayers(_ prayers: [Prayer], for locationId: UUID, year: Int, in context: ModelContext) throws {
        // Validate input parameters
        guard !prayers.isEmpty else {
            print("CacheManager: Skipping annual cache - no prayers to cache")
            return
        }
        
        // Validate all prayers before caching
        do {
            try prayers.validateAll()
        } catch {
            print("CacheManager: Invalid annual prayers data, skipping cache: \(error)")
            throw CacheError.serializationFailed(error)
        }
        
        // Perform operations with proper error handling
        do {
            // Remove existing entry for same location and year with error handling
            try removeAnnualCacheEntry(for: locationId, year: year, in: context)
            
            // Force save after deletion to avoid hash table conflicts
            try context.save()
            
            // Create new cache entry with validation
            let entry = try AnnualCacheEntry(
                locationId: locationId,
                year: year,
                prayers: prayers,
                expiryDays: config.annualCacheExpiryDays
            )
            
            // Insert and save immediately
            context.insert(entry)
            try context.save()
            
            print("CacheManager: Successfully cached \(prayers.count) annual prayers for location \(locationId)")
            
            // Cleanup if needed (with separate error handling)
            do {
                try cleanupAnnualCacheIfNeeded(in: context)
            } catch {
                print("CacheManager: Annual cleanup failed but cache operation succeeded: \(error)")
                // Don't throw - cache operation was successful
            }
            
        } catch {
            print("CacheManager: Failed to cache annual prayers: \(error)")
            throw CacheError.serializationFailed(error)
        }
    }
    
    /// Retrieve cached annual prayer times
    func getCachedAnnualPrayers(for locationId: UUID, year: Int, in context: ModelContext) throws -> [Prayer]? {
        let descriptor = FetchDescriptor<AnnualCacheEntry>(
            predicate: #Predicate { entry in
                entry.locationId == locationId && entry.year == year
            }
        )
        
        guard let entry = try context.fetch(descriptor).first else {
            return nil
        }
        
        // Check if expired
        if entry.isExpired {
            context.delete(entry)
            try context.save()
            return nil
        }
        
        return try entry.getPrayers()
    }
    
    /// Check if annual cache exists and is valid
    func hasCachedAnnualPrayers(for locationId: UUID, year: Int, in context: ModelContext) throws -> Bool {
        let now = Date()
        
        let descriptor = FetchDescriptor<AnnualCacheEntry>(
            predicate: #Predicate { entry in
                entry.locationId == locationId && entry.year == year && entry.expiresAt > now
            }
        )
        
        let results = try context.fetch(descriptor)
        return !results.isEmpty
    }
    
    // MARK: - Cache Cleanup Operations
    
    /// Perform comprehensive cache cleanup
    func performCleanup(in context: ModelContext) throws {
        try cleanupExpiredEntries(in: context)
        try cleanupDailyCacheIfNeeded(in: context)
        try cleanupAnnualCacheIfNeeded(in: context)
        
        lastCleanupTime = Date()
        print("Cache cleanup completed at \(Date())")
    }
    
    /// Remove expired cache entries
    private func cleanupExpiredEntries(in context: ModelContext) throws {
        let now = Date()
        
        // Clean expired daily entries
        let expiredDailyDescriptor = FetchDescriptor<DailyCacheEntry>(
            predicate: #Predicate { entry in
                entry.expiresAt <= now
            }
        )
        
        let expiredDailyEntries = try context.fetch(expiredDailyDescriptor)
        for entry in expiredDailyEntries {
            context.delete(entry)
        }
        
        // Clean expired annual entries
        let expiredAnnualDescriptor = FetchDescriptor<AnnualCacheEntry>(
            predicate: #Predicate { entry in
                entry.expiresAt <= now
            }
        )
        
        let expiredAnnualEntries = try context.fetch(expiredAnnualDescriptor)
        for entry in expiredAnnualEntries {
            context.delete(entry)
        }
        
        try context.save()
        
        if !expiredDailyEntries.isEmpty || !expiredAnnualEntries.isEmpty {
            print("Cleaned up \(expiredDailyEntries.count) daily and \(expiredAnnualEntries.count) annual expired entries")
        }
    }
    
    /// Cleanup daily cache if it exceeds limits
    private func cleanupDailyCacheIfNeeded(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<DailyCacheEntry>(
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .forward)]
        )
        
        let entries = try context.fetch(descriptor)
        
        if entries.count > config.maxDailyEntries {
            let entriesToRemove = entries.prefix(entries.count - config.maxDailyEntries)
            for entry in entriesToRemove {
                context.delete(entry)
            }
            try context.save()
            print("Cleaned up \(entriesToRemove.count) old daily cache entries")
        }
    }
    
    /// Cleanup annual cache if it exceeds limits
    private func cleanupAnnualCacheIfNeeded(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<AnnualCacheEntry>(
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .forward)]
        )
        
        let entries = try context.fetch(descriptor)
        
        if entries.count > config.maxAnnualEntries {
            let entriesToRemove = entries.prefix(entries.count - config.maxAnnualEntries)
            for entry in entriesToRemove {
                context.delete(entry)
            }
            try context.save()
            print("Cleaned up \(entriesToRemove.count) old annual cache entries")
        }
    }
    
    // MARK: - Cache Statistics
    
    /// Get cache statistics
    func getCacheStatistics(in context: ModelContext) throws -> CacheStatistics {
        let dailyDescriptor = FetchDescriptor<DailyCacheEntry>()
        let annualDescriptor = FetchDescriptor<AnnualCacheEntry>()
        
        let dailyEntries = try context.fetch(dailyDescriptor)
        let annualEntries = try context.fetch(annualDescriptor)
        
        let totalDailySize = dailyEntries.reduce(0) { $0 + $1.prayersData.count }
        let totalAnnualSize = annualEntries.reduce(0) { $0 + $1.dataSize }
        
        let expiredDaily = dailyEntries.filter { $0.isExpired }.count
        let expiredAnnual = annualEntries.filter { $0.isExpired }.count
        
        return CacheStatistics(
            dailyEntries: dailyEntries.count,
            annualEntries: annualEntries.count,
            totalDailySize: totalDailySize,
            totalAnnualSize: totalAnnualSize,
            expiredDailyEntries: expiredDaily,
            expiredAnnualEntries: expiredAnnual,
            lastCleanupTime: lastCleanupTime
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func removeDailyCacheEntry(for locationId: UUID, date: Date, in context: ModelContext) throws {
        let startOfDay = Calendar.current.startOfDay(for: date)
        
        do {
            let descriptor = FetchDescriptor<DailyCacheEntry>(
                predicate: #Predicate { entry in
                    entry.locationId == locationId && entry.date == startOfDay
                }
            )
            
            let existingEntries = try context.fetch(descriptor)
            
            if !existingEntries.isEmpty {
                print("CacheManager: Removing \(existingEntries.count) existing daily cache entries")
                
                // Delete entries one by one with validation
                for entry in existingEntries {
                    // Validate entry before deletion
                    guard entry.id.uuidString.count == 36 else {
                        print("CacheManager: Skipping invalid entry with corrupt ID")
                        continue
                    }
                    
                    context.delete(entry)
                }
            }
        } catch {
            print("CacheManager: Error removing daily cache entries: \(error)")
            throw error
        }
    }
    
    private func removeAnnualCacheEntry(for locationId: UUID, year: Int, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<AnnualCacheEntry>(
            predicate: #Predicate { entry in
                entry.locationId == locationId && entry.year == year
            }
        )
        
        let existingEntries = try context.fetch(descriptor)
        for entry in existingEntries {
            context.delete(entry)
        }
    }
    
    private func schedulePeriodicCleanup() {
        // Schedule cleanup every 24 hours
        Timer.scheduledTimer(withTimeInterval: TimeInterval(config.cleanupIntervalHours * 3600), repeats: true) { _ in
            Task {
                // Note: In a real implementation, you'd need access to ModelContext here
                // This would typically be handled by the main service that has context access
                print("Periodic cleanup timer fired - cleanup should be performed by main service")
            }
        }
    }
}

// MARK: - Cache Statistics

struct CacheStatistics {
    let dailyEntries: Int
    let annualEntries: Int
    let totalDailySize: Int
    let totalAnnualSize: Int
    let expiredDailyEntries: Int
    let expiredAnnualEntries: Int
    let lastCleanupTime: Date?
    
    var totalSize: Int {
        return totalDailySize + totalAnnualSize
    }
    
    var totalEntries: Int {
        return dailyEntries + annualEntries
    }
    
    var totalExpiredEntries: Int {
        return expiredDailyEntries + expiredAnnualEntries
    }
    
    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalSize))
    }
}

// MARK: - Cache Error Types

enum CacheError: LocalizedError {
    case serializationFailed(Error)
    case deserializationFailed(Error)
    case cacheCorrupted
    case cacheFull
    case entryNotFound
    
    var errorDescription: String? {
        switch self {
        case .serializationFailed(let error):
            return "Failed to serialize data for caching: \(error.localizedDescription)"
        case .deserializationFailed(let error):
            return "Failed to deserialize cached data: \(error.localizedDescription)"
        case .cacheCorrupted:
            return "Cache data is corrupted and needs to be cleared"
        case .cacheFull:
            return "Cache is full and cannot store more data"
        case .entryNotFound:
            return "Requested cache entry was not found"
        }
    }
}