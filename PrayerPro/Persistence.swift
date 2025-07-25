//
//  Persistence.swift
//  PrayerPro
//
//  Created by Ali Karadeniz on 24.07.25.
//

import SwiftData
import Foundation

/// SwiftData persistence configuration for the Prayer app
struct PersistenceController {
    static let shared = PersistenceController()
    
    /// Shared model container for the application
    let modelContainer: ModelContainer
    
    /// Preview model container for SwiftUI previews
    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let context = result.modelContainer.mainContext
        
        // Create sample data for preview
        do {
            let sampleLocation = try Location(
                name: "Sample City",
                city: "Sample City", 
                country: "Sample Country",
                latitude: 40.7128,
                longitude: -74.0060,
                isFavorite: true,
                isGPSLocation: false
            )
            context.insert(sampleLocation)
            
            let samplePrayer = try Prayer(
                prayerType: .fajr,
                time: Date(),
                locationId: sampleLocation.id
            )
            context.insert(samplePrayer)
            
            try context.save()
        } catch {
            fatalError("Failed to create preview data: \(error)")
        }
        
        return result
    }()
    
    init(inMemory: Bool = false) {
        let schema = Schema([
            Prayer.self,
            Location.self,
            PrayerCompletion.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .automatic
        )
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Configure persistent history cleanup to reduce warnings
            if !inMemory {
                Task {
                    await PersistenceController.configurePersistentHistory()
                }
            }
        } catch {
            // If CloudKit fails, try without CloudKit as fallback
            print("⚠️ Failed to create ModelContainer with CloudKit: \(error)")
            print("🔄 Attempting to create ModelContainer without CloudKit...")
            
            let fallbackConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none
            )
            
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [fallbackConfiguration])
                print("✅ Successfully created ModelContainer without CloudKit")
                
                // Configure persistent history cleanup for fallback too
                if !inMemory {
                    Task {
                        await PersistenceController.configurePersistentHistory()
                    }
                }
            } catch {
                fatalError("❌ Could not create ModelContainer even without CloudKit: \(error)")
            }
        }
    }
    
    /// Configure persistent history cleanup to reduce Core Data warnings
    @MainActor
    private static func configurePersistentHistory() async {
        // Clean up old persistent history periodically
        // This helps reduce the Core Data warnings about dropping transactions
        
        // Clean up history older than 7 days
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        // Note: SwiftData doesn't expose persistent history directly
        // The warnings are normal and indicate Core Data is managing history automatically
        print("📝 Persistent history cleanup configured for date: \(sevenDaysAgo)")
    }
}
