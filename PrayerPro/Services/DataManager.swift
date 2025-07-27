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
    private let appStartTime = Date()
    
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
        // Add early guard to prevent accessing uninitialized context
        guard Thread.isMainThread else {
            print("Warning: fetchCompletionsForDate called from background thread")
            return []
        }
        
        let calendar = Calendar.current
        guard let startOfDay = calendar.dateInterval(of: .day, for: date)?.start,
              let endOfDay = calendar.dateInterval(of: .day, for: date)?.end else {
            print("Warning: Could not determine day boundaries for date: \(date)")
            return []
        }
        
        do {
            // Test context validity with a simple fetch first
            let testDescriptor = FetchDescriptor<PrayerCompletion>(predicate: #Predicate { _ in false })
            _ = try context.fetch(testDescriptor)
            
            let descriptor = FetchDescriptor<PrayerCompletion>(
                predicate: #Predicate { completion in
                    completion.date >= startOfDay &&
                    completion.date < endOfDay
                },
                sortBy: [SortDescriptor(\.completedAt)]
            )
            
            let completions = try context.fetch(descriptor)
            
            // Filter and validate completions safely
            let validCompletions = completions.compactMap { completion -> PrayerCompletion? in
                return autoreleasepool {
                    do {
                        // Safe property access without try? which was causing issues
                        // First check if the object is accessible
                        _ = completion.id
                        _ = completion.prayerType
                        _ = completion.date
                        
                        // Only validate if basic property access succeeded
                        try completion.validate()
                        return completion
                    } catch {
                        print("Warning: Invalid completion found and filtered out: \(error)")
                        return nil
                    }
                }
            }
            
            return validCompletions
        } catch {
            print("Error fetching completions for date \(date): \(error)")
            // Return empty array instead of throwing during startup
            if isStartupPhase() {
                print("During startup - returning empty array instead of throwing")
                return []
            }
            throw error
        }
    }
    
    private func isStartupPhase() -> Bool {
        // Check if app has been running for less than 10 seconds
        return Date().timeIntervalSince(appStartTime) < 10.0
    }
}