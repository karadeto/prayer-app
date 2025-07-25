//
//  DataManager.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData

@Observable
class DataManager {
    static let shared = DataManager()
    
    private init() {}
    
    // MARK: - Location Management
    func saveLocation(_ location: Location, in context: ModelContext) throws {
        context.insert(location)
        try context.save()
    }
    
    func deleteLocation(_ location: Location, in context: ModelContext) throws {
        context.delete(location)
        try context.save()
    }
    
    func fetchFavoriteLocations(in context: ModelContext) throws -> [Location] {
        let descriptor = FetchDescriptor<Location>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }
    
    func fetchGPSLocation(in context: ModelContext) throws -> Location? {
        let descriptor = FetchDescriptor<Location>(
            predicate: #Predicate { $0.isGPSLocation == true }
        )
        return try context.fetch(descriptor).first
    }
    
    // MARK: - Prayer Management
    func savePrayer(_ prayer: Prayer, in context: ModelContext) throws {
        context.insert(prayer)
        try context.save()
    }
    
    func fetchPrayersForLocation(_ locationId: UUID, date: Date, in context: ModelContext) throws -> [Prayer] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let descriptor = FetchDescriptor<Prayer>(
            predicate: #Predicate { prayer in
                prayer.locationId == locationId &&
                prayer.time >= startOfDay &&
                prayer.time < endOfDay
            },
            sortBy: [SortDescriptor(\.time)]
        )
        return try context.fetch(descriptor)
    }
    
    // MARK: - Prayer Completion Management
    func markPrayerComplete(_ prayer: Prayer, in context: ModelContext) throws {
        try prayer.markCompleted()
        
        // Create completion record
        let completion = try PrayerCompletion(
            prayerType: prayer.prayerType,
            date: prayer.time,
            locationId: prayer.locationId
        )
        context.insert(completion)
        
        try context.save()
    }
    
    func fetchCompletionsForDate(_ date: Date, in context: ModelContext) throws -> [PrayerCompletion] {
        // ModelContext in SwiftData doesn't have isInvalidated like Core Data
        // Instead, we'll catch any potential context issues during fetch
        
        let calendar = Calendar.current
        guard let startOfDay = calendar.dateInterval(of: .day, for: date)?.start,
              let endOfDay = calendar.dateInterval(of: .day, for: date)?.end else {
            print("Warning: Could not determine day boundaries for date: \(date)")
            return []
        }
        
        do {
            let descriptor = FetchDescriptor<PrayerCompletion>(
                predicate: #Predicate { completion in
                    completion.date >= startOfDay &&
                    completion.date < endOfDay
                },
                sortBy: [SortDescriptor(\.completedAt)]
            )
            
            let completions = try context.fetch(descriptor)
            
            // Validate completions before returning and filter safely
            let validCompletions = completions.compactMap { completion -> PrayerCompletion? in
                // Safe property access with exception handling for SwiftData objects
                return autoreleasepool {
                    do {
                        // Use try-catch for property access that might cause EXC_BAD_ACCESS
                        guard let _ = try? completion.id,
                              let _ = try? completion.prayerTypeName else {
                            print("Warning: Completion object properties are inaccessible, skipping")
                            return nil
                        }
                        
                        // Only validate if basic property access succeeded
                        try completion.validate()
                        return completion
                    } catch {
                        print("Warning: Invalid or inaccessible completion found and filtered out: \(error)")
                        return nil
                    }
                }
            }
            
            return validCompletions
        } catch {
            print("Error fetching completions for date \(date): \(error)")
            throw error
        }
    }
}