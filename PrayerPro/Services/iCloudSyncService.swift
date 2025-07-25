//
//  iCloudSyncService.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import CloudKit
import SwiftData

class iCloudSyncService: ObservableObject {
    static let shared = iCloudSyncService()
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let publicDatabase: CKDatabase
    
    // Sync state tracking
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncError: Error?
    
    // Retry configuration
    private let maxRetryAttempts = 3
    private let retryDelay: TimeInterval = 2.0
    
    private init() {
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase
        self.publicDatabase = container.publicCloudDatabase
        
        // Load last sync date from UserDefaults
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }
    
    // MARK: - CloudKit Schema Setup
    
    /// Ensures CloudKit schema is properly configured
    func setupCloudKitSchema() async throws {
        // This would typically be done through CloudKit Dashboard
        // But we can verify the schema exists by attempting to fetch
        do {
            // Use a simple predicate that CloudKit can handle
            let query = CKQuery(recordType: "PrayerCompletion", predicate: NSPredicate(value: true))
            let (_, _) = try await privateDatabase.records(matching: query, resultsLimit: 1)
            print("✅ CloudKit schema verified successfully")
        } catch let error as CKError where error.code == .unknownItem {
            print("❌ CloudKit schema needs to be configured in CloudKit Dashboard")
            throw iCloudSyncError.schemaNotConfigured
        } catch {
            print("❌ CloudKit schema verification failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Account Status
    
    /// Check if iCloud account is available
    func checkAccountStatus() async throws -> CKAccountStatus {
        return try await container.accountStatus()
    }
    
    /// Verify iCloud is available for syncing
    func verifyiCloudAvailability() async throws {
        do {
            let status = try await checkAccountStatus()
            
            switch status {
            case .available:
                // Also verify container configuration
                try await verifyContainerConfiguration()
                return
            case .noAccount:
                throw iCloudSyncError.noiCloudAccount
            case .restricted:
                throw iCloudSyncError.iCloudRestricted
            case .couldNotDetermine:
                throw iCloudSyncError.iCloudUnavailable
            case .temporarilyUnavailable:
                throw iCloudSyncError.iCloudTemporarilyUnavailable
            @unknown default:
                throw iCloudSyncError.iCloudUnavailable
            }
        } catch let error as CKError {
            print("❌ CloudKit account verification failed: \(error.localizedDescription)")
            throw handleCloudKitError(error)
        }
    }
    
    /// Verify CloudKit container is properly configured
    private func verifyContainerConfiguration() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { recordID, error in
                if let error = error {
                    let ckError = error as? CKError
                    if ckError?.code == .notAuthenticated {
                        continuation.resume(throwing: iCloudSyncError.noiCloudAccount)
                    } else if ckError?.code == .networkUnavailable || ckError?.code == .networkFailure {
                        continuation.resume(throwing: iCloudSyncError.networkUnavailable)
                    } else {
                        print("❌ CloudKit container configuration error: \(error.localizedDescription)")
                        continuation.resume(throwing: iCloudSyncError.containerNotConfigured)
                    }
                } else if let recordID = recordID {
                    print("✅ CloudKit container verified with user ID: \(recordID.recordName)")
                    continuation.resume(returning: ())
                } else {
                    print("❌ CloudKit container verification failed: No record ID returned")
                    continuation.resume(throwing: iCloudSyncError.containerNotConfigured)
                }
            }
        }
    }
    
    // MARK: - Sync Prayer Completions
    
    /// Sync a single prayer completion to iCloud
    func syncCompletionToiCloud(_ completion: PrayerCompletion) async throws {
        try await verifyiCloudAvailability()
        
        let record = createCloudKitRecord(from: completion)
        
        do {
            _ = try await privateDatabase.save(record)
            completion.markSyncedToiCloud()
            print("Successfully synced completion to iCloud: \(completion.prayerType.displayName)")
        } catch let error as CKError {
            print("CloudKit sync error: \(error.localizedDescription)")
            throw handleCloudKitError(error)
        }
    }
    
    /// Sync multiple completions with retry logic
    func syncCompletionsToiCloud(_ completions: [PrayerCompletion]) async throws {
        guard !completions.isEmpty else { return }
        
        isSyncing = true
        syncError = nil
        
        defer {
            isSyncing = false
        }
        
        var failedCompletions: [PrayerCompletion] = []
        
        for completion in completions {
            do {
                try await syncCompletionToiCloud(completion)
                
                // Small delay to avoid overwhelming CloudKit
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
            } catch {
                print("Failed to sync completion: \(error)")
                failedCompletions.append(completion)
            }
        }
        
        // Retry failed completions
        if !failedCompletions.isEmpty {
            try await retryFailedSyncs(failedCompletions)
        }
        
        // Update last sync date
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
    }
    
    /// Sync all unsynced completions
    func syncAllUnsyncedCompletions(in context: ModelContext) async throws {
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { $0.syncedToiCloud == false }
        )
        
        let unsyncedCompletions = try context.fetch(descriptor)
        
        if !unsyncedCompletions.isEmpty {
            print("Syncing \(unsyncedCompletions.count) unsynced completions to iCloud")
            try await syncCompletionsToiCloud(unsyncedCompletions)
            
            // Save context to persist sync status updates
            try context.save()
        }
    }
    
    // MARK: - Download from iCloud
    
    /// Fetch completions from iCloud for a date range
    func fetchCompletionsFromiCloud(from startDate: Date, to endDate: Date) async throws -> [CKRecord] {
        try await verifyiCloudAvailability()
        
        let predicate = NSPredicate(format: "date >= %@ AND date <= %@", startDate as NSDate, endDate as NSDate)
        let query = CKQuery(recordType: "PrayerCompletion", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        
        do {
            let (matchResults, _) = try await privateDatabase.records(matching: query, resultsLimit: 100)
            
            var records: [CKRecord] = []
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    records.append(record)
                case .failure(let error):
                    print("Failed to fetch record: \(error)")
                }
            }
            
            return records
        } catch let error as CKError {
            throw handleCloudKitError(error)
        }
    }
    
    /// Sync completions from iCloud to local storage
    func syncCompletionsFromiCloud(in context: ModelContext) async throws {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let records = try await fetchCompletionsFromiCloud(from: thirtyDaysAgo, to: Date())
        
        var newCompletions: [PrayerCompletion] = []
        
        for record in records {
            if let completion = try? createPrayerCompletion(from: record) {
                // Check if completion already exists locally
                let completionId = completion.id
                let existingDescriptor = FetchDescriptor<PrayerCompletion>(
                    predicate: #Predicate<PrayerCompletion> { $0.id == completionId }
                )
                
                let existingCompletions = try context.fetch(existingDescriptor)
                
                if existingCompletions.isEmpty {
                    newCompletions.append(completion)
                }
            }
        }
        
        // Insert new completions
        for completion in newCompletions {
            context.insert(completion)
        }
        
        if !newCompletions.isEmpty {
            try context.save()
            print("Downloaded \(newCompletions.count) new completions from iCloud")
        }
    }
    
    // MARK: - Conflict Resolution
    
    /// Resolve conflicts between local and remote completions
    func resolveConflicts(localCompletion: PrayerCompletion, remoteRecord: CKRecord) -> PrayerCompletion {
        // Use the completion with the later completedAt timestamp
        guard let remoteCompletedAt = remoteRecord["completedAt"] as? Date else {
            return localCompletion
        }
        
        if localCompletion.completedAt > remoteCompletedAt {
            // Local is newer, keep local
            return localCompletion
        } else {
            // Remote is newer, update local with remote data
            do {
                let updatedCompletion = try createPrayerCompletion(from: remoteRecord)
                return updatedCompletion
            } catch {
                print("Failed to create completion from remote record: \(error)")
                return localCompletion
            }
        }
    }
    
    // MARK: - Retry Logic
    
    private func retryFailedSyncs(_ completions: [PrayerCompletion]) async throws {
        for attempt in 1...maxRetryAttempts {
            print("Retry attempt \(attempt) for \(completions.count) failed completions")
            
            var stillFailing: [PrayerCompletion] = []
            
            for completion in completions {
                do {
                    try await syncCompletionToiCloud(completion)
                } catch {
                    stillFailing.append(completion)
                }
            }
            
            if stillFailing.isEmpty {
                print("All retries successful")
                return
            }
            
            if attempt < maxRetryAttempts {
                let delay = retryDelay * Double(attempt) // Exponential backoff
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        print("Some completions still failed after \(maxRetryAttempts) attempts")
        syncError = iCloudSyncError.maxRetriesExceeded
    }
    
    // MARK: - Helper Methods
    
    private func createCloudKitRecord(from completion: PrayerCompletion) -> CKRecord {
        let recordID = CKRecord.ID(recordName: completion.id.uuidString)
        let record = CKRecord(recordType: "PrayerCompletion", recordID: recordID)
        
        record["prayerType"] = completion.prayerTypeName
        record["date"] = completion.date
        record["completedAt"] = completion.completedAt
        record["locationId"] = completion.locationId.uuidString
        record["createdAt"] = Date() // Add creation timestamp for CloudKit
        
        return record
    }
    
    private func createPrayerCompletion(from record: CKRecord) throws -> PrayerCompletion {
        guard let prayerTypeName = record["prayerType"] as? String,
              let date = record["date"] as? Date,
              let completedAt = record["completedAt"] as? Date,
              let locationIdString = record["locationId"] as? String,
              let locationId = UUID(uuidString: locationIdString),
              let prayerType = PrayerType(rawValue: prayerTypeName) else {
            throw iCloudSyncError.invalidRecordData
        }
        
        let completionId = UUID(uuidString: record.recordID.recordName) ?? UUID()
        
        return try PrayerCompletion(
            id: completionId,
            prayerType: prayerType,
            date: date,
            completedAt: completedAt,
            locationId: locationId,
            syncedToiCloud: true
        )
    }
    
    private func handleCloudKitError(_ error: CKError) -> Error {
        switch error.code {
        case .networkUnavailable, .networkFailure:
            return iCloudSyncError.networkUnavailable
        case .quotaExceeded:
            return iCloudSyncError.quotaExceeded
        case .limitExceeded:
            return iCloudSyncError.rateLimited
        case .serverRecordChanged:
            return iCloudSyncError.conflictDetected
        case .zoneNotFound, .unknownItem:
            return iCloudSyncError.schemaNotConfigured
        default:
            return iCloudSyncError.cloudKitError(error)
        }
    }
}

// MARK: - Error Types

enum iCloudSyncError: LocalizedError {
    case noiCloudAccount
    case iCloudRestricted
    case iCloudUnavailable
    case iCloudTemporarilyUnavailable
    case networkUnavailable
    case quotaExceeded
    case rateLimited
    case conflictDetected
    case schemaNotConfigured
    case containerNotConfigured
    case invalidRecordData
    case maxRetriesExceeded
    case cloudKitError(CKError)
    
    var errorDescription: String? {
        switch self {
        case .noiCloudAccount:
            return "No iCloud account is configured on this device"
        case .iCloudRestricted:
            return "iCloud access is restricted on this device"
        case .iCloudUnavailable:
            return "iCloud is currently unavailable"
        case .iCloudTemporarilyUnavailable:
            return "iCloud is temporarily unavailable"
        case .networkUnavailable:
            return "Network connection is unavailable"
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
        case .rateLimited:
            return "Too many requests to iCloud, please try again later"
        case .conflictDetected:
            return "Data conflict detected, resolving automatically"
        case .schemaNotConfigured:
            return "CloudKit schema not configured properly"
        case .containerNotConfigured:
            return "CloudKit container not configured in Apple Developer portal"
        case .invalidRecordData:
            return "Invalid data received from iCloud"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded"
        case .cloudKitError(let ckError):
            return "CloudKit error: \(ckError.localizedDescription)"
        }
    }
}