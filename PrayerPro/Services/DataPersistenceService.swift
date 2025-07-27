//
//  DataPersistenceService.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData
import AppKit

// MARK: - Data Persistence Service

class DataPersistenceService: ObservableObject {
    static let shared = DataPersistenceService()
    
    private var modelContext: ModelContext?
    private let sessionManager = SessionManager.shared
    private let migrationManager = DataMigrationManager.shared
    private let cacheManager = CacheManager.shared
    private let favoriteLocationsManager = FavoriteLocationsManager.shared
    
    // Observable properties
    @Published var isInitialized = false
    @Published var initializationError: Error?
    @Published var lastCleanupDate: Date?
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Initialization
    
    /// Initialize the data persistence service with model context
    func initialize(with context: ModelContext) async {
        self.modelContext = context
        
        do {
            // Perform migration if needed
            try await migrationManager.performMigrationIfNeeded(in: context)
            
            // Validate data integrity after migration
            let isDataValid = try await migrationManager.validateDataIntegrity(in: context)
            if !isDataValid {
                print("⚠️ Data integrity issues detected after migration")
            }
            
            // Initialize favorite locations manager
            favoriteLocationsManager.setModelContext(context)
            
            // Restore session state
            sessionManager.restoreSession()
            
            // Perform initial cleanup
            try await performInitialCleanup(in: context)
            
            await MainActor.run {
                self.isInitialized = true
                self.initializationError = nil
            }
            
            print("✅ Data persistence service initialized successfully")
            
        } catch {
            await MainActor.run {
                self.initializationError = error
                self.isInitialized = false
            }
            
            print("❌ Failed to initialize data persistence service: \(error)")
        }
    }
    
    // MARK: - Session Management
    
    /// Save current session state
    func saveSession() {
        sessionManager.saveSession()
    }
    
    /// Update selected location in session
    func updateSelectedLocation(_ location: Location?) {
        sessionManager.updateSelectedLocation(location)
    }
    
    /// Restore last selected location
    func restoreLastSelectedLocation() async -> Location? {
        guard let context = modelContext else { return nil }
        return await sessionManager.restoreLastSelectedLocation(in: context)
    }
    
    /// Get session information
    func getSessionInfo() -> (isFresh: Bool, hasVersionChanged: Bool, isStale: Bool) {
        return (
            isFresh: sessionManager.isFreshLaunch,
            hasVersionChanged: sessionManager.hasAppVersionChanged,
            isStale: sessionManager.isSessionStale
        )
    }
    
    // MARK: - Data Management
    
    /// Save location with proper persistence
    func saveLocation(_ location: Location) async throws {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        try await MainActor.run {
            context.insert(location)
            try context.save()
        }
        
        // Update session if this is the selected location
        if location.id == sessionManager.selectedLocationId {
            sessionManager.updateSelectedLocation(location)
        }
    }
    
    /// Delete location with cleanup
    func deleteLocation(_ location: Location) async throws {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        try await MainActor.run {
            // Clean up related cache entries
            try cacheManager.cleanupCacheForDeletedLocations(in: context)
            
            // Delete the location
            context.delete(location)
            try context.save()
        }
        
        // Update session if this was the selected location
        if location.id == sessionManager.selectedLocationId {
            sessionManager.updateSelectedLocation(nil)
        }
    }
    
    /// Save prayer with validation
    func savePrayer(_ prayer: Prayer) async throws {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        // Validate prayer before saving
        try prayer.validate()
        
        try await MainActor.run {
            context.insert(prayer)
            try context.save()
        }
    }
    
    /// Save prayer completion with iCloud sync
    func savePrayerCompletion(_ completion: PrayerCompletion) async throws {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        // Validate completion before saving
        try completion.validate()
        
        try await MainActor.run {
            context.insert(completion)
            try context.save()
        }
        
        // Trigger iCloud sync if available
        Task {
            do {
                try await PrayerCompletionManager.shared.syncUnsyncedCompletions(in: context)
            } catch {
                print("Failed to sync completion to iCloud: \(error)")
                // Don't throw - local save was successful
            }
        }
    }
    
    // MARK: - Cache Management
    
    /// Cache daily prayers with automatic cleanup
    func cacheDailyPrayers(_ prayers: [Prayer], for locationId: UUID, date: Date) async throws {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        try cacheManager.cacheDailyPrayers(prayers, for: locationId, date: date, in: context)
    }
    
    /// Cache annual prayers with automatic cleanup
    func cacheAnnualPrayers(_ prayers: [Prayer], for locationId: UUID, year: Int) async throws {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        try cacheManager.cacheAnnualPrayers(prayers, for: locationId, year: year, in: context)
    }
    
    /// Get cached daily prayers
    func getCachedDailyPrayers(for locationId: UUID, date: Date) async throws -> [Prayer]? {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        return try cacheManager.getCachedDailyPrayers(for: locationId, date: date, in: context)
    }
    
    /// Get cached annual prayers
    func getCachedAnnualPrayers(for locationId: UUID, year: Int) async throws -> [Prayer]? {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        return try cacheManager.getCachedAnnualPrayers(for: locationId, year: year, in: context)
    }
    
    // MARK: - Cleanup Operations
    
    /// Perform comprehensive cleanup
    func performCleanup() async throws {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        try await MainActor.run {
            // Perform cache cleanup
            try cacheManager.performCleanup(in: context)
            
            // Perform intelligent cleanup
            try cacheManager.performIntelligentCleanup(in: context)
            
            // Clean up orphaned cache entries
            try cacheManager.cleanupCacheForDeletedLocations(in: context)
            
            // Clean up old prayer completions (older than 1 year)
            try cleanupOldPrayerCompletions(in: context)
            
            // Clean up old prayers (older than 30 days for non-favorites)
            try cleanupOldPrayers(in: context)
        }
        
        lastCleanupDate = Date()
        print("✅ Comprehensive cleanup completed")
    }
    
    /// Get system health report
    func getSystemHealthReport() async throws -> SystemHealthReport {
        guard let context = modelContext else {
            throw PersistenceError.contextNotAvailable
        }
        
        let cacheHealth = try cacheManager.getCacheHealthReport(in: context)
        let dataStats = try await migrationManager.getDataStatistics(in: context)
        let sessionInfo = getSessionInfo()
        
        return SystemHealthReport(
            cacheHealth: cacheHealth,
            dataStatistics: dataStats,
            sessionInfo: sessionInfo,
            lastCleanupDate: lastCleanupDate,
            isInitialized: isInitialized
        )
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        // Listen for cache cleanup requests
        NotificationCenter.default.addObserver(
            forName: Notification.Name("PerformCacheCleanup"),
            object: nil,
            queue: .main
        ) { _ in
            Task {
                do {
                    try await self.performCleanup()
                } catch {
                    print("Scheduled cleanup failed: \(error)")
                }
            }
        }
        
        // Listen for app termination to save session
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.saveSession()
        }
        
        // Listen for app becoming inactive to save session
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.saveSession()
        }
    }
    
    private func performInitialCleanup(in context: ModelContext) async throws {
        // Perform a light cleanup on startup
        try cacheManager.performCleanup(in: context)
        
        // Clean up orphaned cache entries
        try cacheManager.cleanupCacheForDeletedLocations(in: context)
        
        lastCleanupDate = Date()
    }
    
    private func cleanupOldPrayerCompletions(in context: ModelContext) throws {
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)
        
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { completion in
                completion.date < oneYearAgo
            }
        )
        
        let oldCompletions = try context.fetch(descriptor)
        for completion in oldCompletions {
            context.delete(completion)
        }
        
        if !oldCompletions.isEmpty {
            try context.save()
            print("Cleaned up \(oldCompletions.count) old prayer completions")
        }
    }
    
    private func cleanupOldPrayers(in context: ModelContext) throws {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        
        // Only clean up prayers for non-favorite locations
        let locationDescriptor = FetchDescriptor<Location>(
            predicate: #Predicate { location in
                location.isFavorite == false
            }
        )
        
        let nonFavoriteLocations = try context.fetch(locationDescriptor)
        let nonFavoriteLocationIds = Set(nonFavoriteLocations.map { $0.id })
        
        let prayerDescriptor = FetchDescriptor<Prayer>(
            predicate: #Predicate { prayer in
                prayer.time < thirtyDaysAgo
            }
        )
        
        let oldPrayers = try context.fetch(prayerDescriptor)
        let prayersToDelete = oldPrayers.filter { nonFavoriteLocationIds.contains($0.locationId) }
        
        for prayer in prayersToDelete {
            context.delete(prayer)
        }
        
        if !prayersToDelete.isEmpty {
            try context.save()
            print("Cleaned up \(prayersToDelete.count) old prayers for non-favorite locations")
        }
    }
}

// MARK: - System Health Report

struct SystemHealthReport {
    let cacheHealth: CacheHealthReport
    let dataStatistics: [String: Any]
    let sessionInfo: (isFresh: Bool, hasVersionChanged: Bool, isStale: Bool)
    let lastCleanupDate: Date?
    let isInitialized: Bool
    
    var overallHealthScore: Double {
        var score = cacheHealth.healthScore
        
        // Penalize if cleanup hasn't been done recently
        if let lastCleanup = lastCleanupDate {
            let daysSinceCleanup = Date().timeIntervalSince(lastCleanup) / (24 * 60 * 60)
            if daysSinceCleanup > 7 {
                score *= 0.9 // Reduce score by 10%
            }
        } else {
            score *= 0.8 // Reduce score by 20% if never cleaned up
        }
        
        // Penalize if not initialized
        if !isInitialized {
            score *= 0.5
        }
        
        return max(0.0, min(1.0, score))
    }
    
    var overallHealthStatus: String {
        switch overallHealthScore {
        case 0.9...1.0:
            return "Excellent"
        case 0.7..<0.9:
            return "Good"
        case 0.5..<0.7:
            return "Fair"
        case 0.3..<0.5:
            return "Poor"
        default:
            return "Critical"
        }
    }
    
    var needsMaintenance: Bool {
        return overallHealthScore < 0.7 || cacheHealth.needsCleanup
    }
    
    var recommendations: [String] {
        var recommendations: [String] = []
        
        if cacheHealth.needsCleanup {
            recommendations.append("Perform cache cleanup to remove expired entries")
        }
        
        if let lastCleanup = lastCleanupDate {
            let daysSinceCleanup = Date().timeIntervalSince(lastCleanup) / (24 * 60 * 60)
            if daysSinceCleanup > 7 {
                recommendations.append("Perform system cleanup - last cleanup was \(Int(daysSinceCleanup)) days ago")
            }
        } else {
            recommendations.append("Perform initial system cleanup")
        }
        
        if !isInitialized {
            recommendations.append("Reinitialize data persistence service")
        }
        
        if sessionInfo.isStale {
            recommendations.append("Session is stale - consider refreshing location data")
        }
        
        return recommendations
    }
}

// MARK: - Persistence Error

enum PersistenceError: LocalizedError {
    case contextNotAvailable
    case initializationFailed(Error)
    case migrationFailed(Error)
    case dataCorruption
    case cleanupFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .contextNotAvailable:
            return "Model context is not available"
        case .initializationFailed(let error):
            return "Failed to initialize persistence service: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Data migration failed: \(error.localizedDescription)"
        case .dataCorruption:
            return "Data corruption detected"
        case .cleanupFailed(let error):
            return "Cleanup operation failed: \(error.localizedDescription)"
        }
    }
}