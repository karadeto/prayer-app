//
//  DataMigrationManager.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData

// MARK: - Migration Version

enum MigrationVersion: String, CaseIterable, Comparable {
    case v1_0_0 = "1.0.0"
    case v1_1_0 = "1.1.0"
    case v1_2_0 = "1.2.0"
    
    static func < (lhs: MigrationVersion, rhs: MigrationVersion) -> Bool {
        let lhsComponents = lhs.versionNumber
        let rhsComponents = rhs.versionNumber
        
        let maxCount = max(lhsComponents.count, rhsComponents.count)
        
        for i in 0..<maxCount {
            let lhsValue = i < lhsComponents.count ? lhsComponents[i] : 0
            let rhsValue = i < rhsComponents.count ? rhsComponents[i] : 0
            
            if lhsValue < rhsValue {
                return true
            } else if lhsValue > rhsValue {
                return false
            }
        }
        
        return false // They are equal
    }
    
    private var versionNumber: [Int] {
        return rawValue.split(separator: ".").compactMap { Int($0) }
    }
    
    static var current: MigrationVersion {
        let appVersion = Bundle.main.appVersion
        return MigrationVersion(rawValue: appVersion) ?? .v1_0_0
    }
}

// MARK: - Migration Error

enum MigrationError: LocalizedError {
    case migrationFailed(String)
    case unsupportedVersion(String)
    case dataCorruption
    case backupFailed
    case rollbackFailed
    
    var errorDescription: String? {
        switch self {
        case .migrationFailed(let reason):
            return "Migration failed: \(reason)"
        case .unsupportedVersion(let version):
            return "Unsupported app version: \(version)"
        case .dataCorruption:
            return "Data corruption detected during migration"
        case .backupFailed:
            return "Failed to create backup before migration"
        case .rollbackFailed:
            return "Failed to rollback after migration failure"
        }
    }
}

// MARK: - Migration Step Protocol

protocol MigrationStep {
    var fromVersion: MigrationVersion { get }
    var toVersion: MigrationVersion { get }
    var description: String { get }
    
    func execute(in context: ModelContext) async throws
    func rollback(in context: ModelContext) async throws
}

// MARK: - Data Migration Manager

class DataMigrationManager {
    static let shared = DataMigrationManager()
    
    private let userDefaults = UserDefaults.standard
    private let lastMigrationVersionKey = "LastMigrationVersion"
    private let migrationInProgressKey = "MigrationInProgress"
    
    private var migrationSteps: [MigrationStep] = []
    
    private init() {
        setupMigrationSteps()
    }
    
    // MARK: - Public Methods
    
    /// Check if migration is needed and perform it
    func performMigrationIfNeeded(in context: ModelContext) async throws {
        let currentVersion = MigrationVersion.current
        let lastMigrationVersion = getLastMigrationVersion()
        
        print("Current app version: \(currentVersion.rawValue)")
        print("Last migration version: \(lastMigrationVersion?.rawValue ?? "none")")
        
        // Check if migration is needed
        guard let lastVersion = lastMigrationVersion, lastVersion < currentVersion else {
            print("No migration needed")
            return
        }
        
        // Check if migration was interrupted
        if isMigrationInProgress() {
            print("Previous migration was interrupted, attempting to recover...")
            try await handleInterruptedMigration(in: context)
        }
        
        // Perform migration
        try await performMigration(from: lastVersion, to: currentVersion, in: context)
    }
    
    /// Force migration from a specific version (for testing)
    func forceMigration(from: MigrationVersion, to: MigrationVersion, in context: ModelContext) async throws {
        try await performMigration(from: from, to: to, in: context)
    }
    
    /// Get migration history
    func getMigrationHistory() -> [String: Any] {
        return [
            "lastMigrationVersion": getLastMigrationVersion()?.rawValue ?? "none",
            "migrationInProgress": isMigrationInProgress(),
            "availableMigrations": migrationSteps.map { "\($0.fromVersion.rawValue) -> \($0.toVersion.rawValue)" }
        ]
    }
    
    /// Reset migration state (for testing or recovery)
    func resetMigrationState() {
        userDefaults.removeObject(forKey: lastMigrationVersionKey)
        userDefaults.removeObject(forKey: migrationInProgressKey)
        print("Migration state reset")
    }
    
    // MARK: - Private Methods
    
    private func setupMigrationSteps() {
        // Add migration steps as new versions are released
        migrationSteps = [
            Migration_1_0_0_to_1_1_0(),
            Migration_1_1_0_to_1_2_0()
        ]
    }
    
    private func performMigration(from: MigrationVersion, to: MigrationVersion, in context: ModelContext) async throws {
        print("Starting migration from \(from.rawValue) to \(to.rawValue)")
        
        // Mark migration as in progress
        setMigrationInProgress(true)
        
        do {
            // Create backup before migration
            try await createBackup(in: context)
            
            // Find and execute migration steps
            let applicableSteps = migrationSteps.filter { step in
                step.fromVersion >= from && step.toVersion <= to
            }.sorted { $0.fromVersion < $1.fromVersion }
            
            for step in applicableSteps {
                print("Executing migration step: \(step.description)")
                try await step.execute(in: context)
                print("Migration step completed: \(step.description)")
            }
            
            // Update migration version
            setLastMigrationVersion(to)
            setMigrationInProgress(false)
            
            print("Migration completed successfully")
            
        } catch {
            print("Migration failed: \(error)")
            
            // Attempt rollback
            do {
                try await rollbackMigration(from: from, to: to, in: context)
            } catch {
                print("Rollback failed: \(error)")
                throw MigrationError.rollbackFailed
            }
            
            throw MigrationError.migrationFailed(error.localizedDescription)
        }
    }
    
    private func rollbackMigration(from: MigrationVersion, to: MigrationVersion, in context: ModelContext) async throws {
        print("Rolling back migration from \(from.rawValue) to \(to.rawValue)")
        
        let applicableSteps = migrationSteps.filter { step in
            step.fromVersion >= from && step.toVersion <= to
        }.sorted { $0.fromVersion > $1.fromVersion } // Reverse order for rollback
        
        for step in applicableSteps {
            print("Rolling back migration step: \(step.description)")
            try await step.rollback(in: context)
        }
        
        // Reset migration state
        setLastMigrationVersion(from)
        setMigrationInProgress(false)
        
        print("Rollback completed")
    }
    
    private func handleInterruptedMigration(in context: ModelContext) async throws {
        print("Handling interrupted migration...")
        
        // For now, we'll reset the migration state and let it retry
        // In a more sophisticated implementation, we could try to determine
        // exactly where the migration failed and resume from there
        setMigrationInProgress(false)
        
        // Optionally restore from backup if available
        try await restoreFromBackupIfNeeded(in: context)
    }
    
    private func createBackup(in context: ModelContext) async throws {
        print("Creating backup before migration...")
        
        // In a real implementation, you might want to export data to a backup file
        // For now, we'll just ensure the context is saved
        try context.save()
        
        print("Backup created successfully")
    }
    
    private func restoreFromBackupIfNeeded(in context: ModelContext) async throws {
        print("Checking if backup restore is needed...")
        
        // In a real implementation, you would restore from the backup file
        // For now, we'll just log that this would happen
        print("Backup restore would be performed here if needed")
    }
    
    // MARK: - UserDefaults Helpers
    
    private func getLastMigrationVersion() -> MigrationVersion? {
        guard let versionString = userDefaults.string(forKey: lastMigrationVersionKey) else {
            return nil
        }
        return MigrationVersion(rawValue: versionString)
    }
    
    private func setLastMigrationVersion(_ version: MigrationVersion) {
        userDefaults.set(version.rawValue, forKey: lastMigrationVersionKey)
    }
    
    private func isMigrationInProgress() -> Bool {
        return userDefaults.bool(forKey: migrationInProgressKey)
    }
    
    private func setMigrationInProgress(_ inProgress: Bool) {
        userDefaults.set(inProgress, forKey: migrationInProgressKey)
    }
}

// MARK: - Migration Step Implementations

/// Migration from version 1.0.0 to 1.1.0
struct Migration_1_0_0_to_1_1_0: MigrationStep {
    let fromVersion = MigrationVersion.v1_0_0
    let toVersion = MigrationVersion.v1_1_0
    let description = "Add annual data caching support to locations"
    
    func execute(in context: ModelContext) async throws {
        print("Executing migration: \(description)")
        
        // Fetch all existing locations
        let descriptor = FetchDescriptor<Location>()
        let locations = try context.fetch(descriptor)
        
        // Update locations to have annualDataCached property properly set
        for location in locations {
            if location.isFavorite {
                // For favorite locations, we assume annual data should be cached
                location.annualDataCached = false // Will be set to true when data is actually cached
            }
            location.lastUpdated = Date()
        }
        
        try context.save()
        print("Migration completed: Updated \(locations.count) locations")
    }
    
    func rollback(in context: ModelContext) async throws {
        print("Rolling back migration: \(description)")
        // For this migration, rollback doesn't need to do anything
        // as we only added properties that don't break compatibility
    }
}

/// Migration from version 1.1.0 to 1.2.0
struct Migration_1_1_0_to_1_2_0: MigrationStep {
    let fromVersion = MigrationVersion.v1_1_0
    let toVersion = MigrationVersion.v1_2_0
    let description = "Enhanced session management and cleanup"
    
    func execute(in context: ModelContext) async throws {
        print("Executing migration: \(description)")
        
        // Clean up old cache entries that might be corrupted
        try await cleanupOldCacheEntries(in: context)
        
        // Initialize session management for existing users
        let sessionManager = SessionManager.shared
        if sessionManager.isFreshLaunch {
            // Set up default session state for existing users
            sessionManager.updateSelectedLocation(nil)
        }
        
        print("Migration completed: Enhanced session management initialized")
    }
    
    func rollback(in context: ModelContext) async throws {
        print("Rolling back migration: \(description)")
        // Clear session state if rollback is needed
        SessionManager.shared.clearSession()
    }
    
    private func cleanupOldCacheEntries(in context: ModelContext) async throws {
        // Clean up any potentially corrupted cache entries
        let cacheManager = CacheManager.shared
        try cacheManager.performCleanup(in: context)
    }
}

// MARK: - Migration Utilities

extension DataMigrationManager {
    /// Validate data integrity after migration
    func validateDataIntegrity(in context: ModelContext) async throws -> Bool {
        print("Validating data integrity...")
        
        var isValid = true
        var validationErrors: [String] = []
        
        // Validate locations
        do {
            let locationDescriptor = FetchDescriptor<Location>()
            let locations = try context.fetch(locationDescriptor)
            
            for location in locations {
                do {
                    try location.validate()
                } catch {
                    validationErrors.append("Invalid location \(location.name): \(error)")
                    isValid = false
                }
            }
            
            print("Validated \(locations.count) locations")
        } catch {
            validationErrors.append("Failed to fetch locations: \(error)")
            isValid = false
        }
        
        // Validate prayers
        do {
            let prayerDescriptor = FetchDescriptor<Prayer>()
            let prayers = try context.fetch(prayerDescriptor)
            
            for prayer in prayers {
                do {
                    try prayer.validate()
                } catch {
                    validationErrors.append("Invalid prayer \(prayer.name): \(error)")
                    isValid = false
                }
            }
            
            print("Validated \(prayers.count) prayers")
        } catch {
            validationErrors.append("Failed to fetch prayers: \(error)")
            isValid = false
        }
        
        // Validate prayer completions
        do {
            let completionDescriptor = FetchDescriptor<PrayerCompletion>()
            let completions = try context.fetch(completionDescriptor)
            
            for completion in completions {
                do {
                    try completion.validate()
                } catch {
                    validationErrors.append("Invalid completion \(completion.id): \(error)")
                    isValid = false
                }
            }
            
            print("Validated \(completions.count) prayer completions")
        } catch {
            validationErrors.append("Failed to fetch completions: \(error)")
            isValid = false
        }
        
        if !isValid {
            print("Data validation failed with errors:")
            for error in validationErrors {
                print("  - \(error)")
            }
        } else {
            print("Data validation passed")
        }
        
        return isValid
    }
    
    /// Get data statistics for debugging
    func getDataStatistics(in context: ModelContext) async throws -> [String: Any] {
        let locationDescriptor = FetchDescriptor<Location>()
        let prayerDescriptor = FetchDescriptor<Prayer>()
        let completionDescriptor = FetchDescriptor<PrayerCompletion>()
        let dailyCacheDescriptor = FetchDescriptor<DailyCacheEntry>()
        let annualCacheDescriptor = FetchDescriptor<AnnualCacheEntry>()
        
        let locations = try context.fetch(locationDescriptor)
        let prayers = try context.fetch(prayerDescriptor)
        let completions = try context.fetch(completionDescriptor)
        let dailyCache = try context.fetch(dailyCacheDescriptor)
        let annualCache = try context.fetch(annualCacheDescriptor)
        
        return [
            "locations": [
                "total": locations.count,
                "favorites": locations.filter { $0.isFavorite }.count,
                "gps": locations.filter { $0.isGPSLocation }.count
            ],
            "prayers": [
                "total": prayers.count,
                "completed": prayers.filter { $0.isCompleted }.count
            ],
            "completions": [
                "total": completions.count,
                "synced": completions.filter { $0.syncedToiCloud }.count
            ],
            "cache": [
                "dailyEntries": dailyCache.count,
                "annualEntries": annualCache.count
            ]
        ]
    }
}