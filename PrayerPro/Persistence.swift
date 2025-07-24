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
            PrayerCompletion.self,
            DailyCacheEntry.self,
            AnnualCacheEntry.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .automatic
        )
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
