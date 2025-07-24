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
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let descriptor = FetchDescriptor<PrayerCompletion>(
            predicate: #Predicate { completion in
                completion.date >= startOfDay &&
                completion.date < endOfDay
            },
            sortBy: [SortDescriptor(\.completedAt)]
        )
        return try context.fetch(descriptor)
    }
}