//
//  CloudKitSchemaHelper.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import CloudKit

/// Helper class for CloudKit schema configuration and management
class CloudKitSchemaHelper {
    
    /// CloudKit Record Types
    struct RecordTypes {
        static let prayerCompletion = "PrayerCompletion"
    }
    
    /// CloudKit Field Names for PrayerCompletion
    struct PrayerCompletionFields {
        static let prayerType = "prayerType"
        static let date = "date"
        static let completedAt = "completedAt"
        static let locationId = "locationId"
        static let createdAt = "createdAt"
    }
    
    /// Verify CloudKit schema exists and is properly configured
    static func verifySchema() async throws {
        let container = CKContainer.default()
        let database = container.privateCloudDatabase
        
        // Instead of querying, try to create and immediately delete a test record
        // This verifies the schema exists without needing queryable fields
        let testRecord = createSampleRecord()
        
        do {
            // Try to save the test record
            let savedRecord = try await database.save(testRecord)
            print("✅ CloudKit schema verified successfully")
            
            // Immediately delete the test record to clean up
            try await database.deleteRecord(withID: savedRecord.recordID)
            print("🧹 Test record cleaned up")
            
        } catch let error as CKError {
            switch error.code {
            case .unknownItem:
                print("❌ CloudKit schema not found. Please configure the schema in CloudKit Dashboard.")
                print("📋 Required Record Type: \(RecordTypes.prayerCompletion)")
                print("📋 Required Fields:")
                print("   - \(PrayerCompletionFields.prayerType): String")
                print("   - \(PrayerCompletionFields.date): Date/Time")
                print("   - \(PrayerCompletionFields.completedAt): Date/Time")
                print("   - \(PrayerCompletionFields.locationId): String")
                print("   - \(PrayerCompletionFields.createdAt): Date/Time")
                throw CloudKitSchemaError.schemaNotConfigured
            case .invalidArguments, .constraintViolation:
                print("❌ CloudKit schema validation failed: Missing or incorrectly configured fields")
                print("📋 Please check that all required fields exist with correct types")
                printSchemaInstructions()
                throw CloudKitSchemaError.schemaNotConfigured
            default:
                print("❌ CloudKit schema verification failed: \(error.localizedDescription)")
                throw error
            }
        } catch {
            print("❌ CloudKit schema verification failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Create a sample record for schema validation (development only)
    static func createSampleRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: "sample-\(UUID().uuidString)")
        let record = CKRecord(recordType: RecordTypes.prayerCompletion, recordID: recordID)
        
        record[PrayerCompletionFields.prayerType] = "fajr"
        record[PrayerCompletionFields.date] = Date()
        record[PrayerCompletionFields.completedAt] = Date()
        record[PrayerCompletionFields.locationId] = UUID().uuidString
        record[PrayerCompletionFields.createdAt] = Date()
        
        return record
    }
    
    /// Instructions for manual CloudKit Dashboard configuration
    static func printSchemaInstructions() {
        print("""
        
        📋 CloudKit Schema Configuration Instructions:
        
        1. Open CloudKit Dashboard (https://icloud.developer.apple.com/dashboard/)
        2. Select your app's container
        3. Go to Schema > Record Types
        4. Create a new Record Type named: \(RecordTypes.prayerCompletion)
        5. Add the following fields:
        
           Field Name: \(PrayerCompletionFields.prayerType)
           Type: String
           Queryable: ✅ (recommended)
           
           Field Name: \(PrayerCompletionFields.date)
           Type: Date/Time
           Queryable: ✅ (required for date range queries)
           
           Field Name: \(PrayerCompletionFields.completedAt)
           Type: Date/Time
           Queryable: ✅ (recommended)
           
           Field Name: \(PrayerCompletionFields.locationId)
           Type: String
           Queryable: ✅ (recommended)
           
           Field Name: \(PrayerCompletionFields.createdAt)
           Type: Date/Time
           Queryable: ✅ (recommended)
        
        6. IMPORTANT: Mark the 'date' field as Queryable (required for syncing)
        7. Save the schema
        8. Deploy to Production Environment
        
        Note: If you get "Field not marked queryable" errors, ensure the 'date' field
        is marked as queryable in the CloudKit Dashboard.
        
        """)
    }
}

enum CloudKitSchemaError: LocalizedError {
    case schemaNotConfigured
    case fieldMissing(String)
    case invalidFieldType(String)
    
    var errorDescription: String? {
        switch self {
        case .schemaNotConfigured:
            return "CloudKit schema is not configured. Please set up the required record types in CloudKit Dashboard."
        case .fieldMissing(let field):
            return "Required field '\(field)' is missing from CloudKit schema."
        case .invalidFieldType(let field):
            return "Field '\(field)' has incorrect type in CloudKit schema."
        }
    }
}
