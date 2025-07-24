//
//  FavoriteLocationsManager.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData

// MARK: - Favorite Locations Errors

enum FavoriteLocationsError: LocalizedError {
    case locationAlreadyExists
    case locationNotFound
    case persistenceError(Error)
    case invalidLocation
    case storageLimit
    
    var errorDescription: String? {
        switch self {
        case .locationAlreadyExists:
            return "This location is already in your favorites"
        case .locationNotFound:
            return "Location not found in favorites"
        case .persistenceError(let error):
            return "Failed to save location: \(error.localizedDescription)"
        case .invalidLocation:
            return "Invalid location data"
        case .storageLimit:
            return "Maximum number of favorite locations reached"
        }
    }
}

// MARK: - Favorite Locations Manager Protocol

protocol FavoriteLocationsManagerProtocol {
    func addToFavorites(_ location: Location) async throws
    func removeFromFavorites(_ location: Location) async throws
    func getFavoriteLocations() async throws -> [Location]
    func isFavorite(_ location: Location) async -> Bool
    func updateFavoriteLocation(_ location: Location) async throws
    func clearAllFavorites() async throws
}

// MARK: - Favorite Locations Manager Implementation

@Observable
class FavoriteLocationsManager: FavoriteLocationsManagerProtocol {
    static let shared = FavoriteLocationsManager()
    
    private var modelContext: ModelContext?
    private let maxFavorites = 50 // Reasonable limit for favorites
    
    // Observable properties
    var favoriteLocations: [Location] = []
    var isLoading = false
    var error: Error?
    
    init() {
        Task {
            await loadFavorites()
        }
    }
    
    // MARK: - Setup
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        Task {
            await loadFavorites()
        }
    }
    
    // MARK: - Public Methods
    
    func addToFavorites(_ location: Location) async throws {
        guard let context = modelContext else {
            throw FavoriteLocationsError.persistenceError(NSError(domain: "ModelContext", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model context not available"]))
        }
        
        // Validate location
        try location.validate()
        
        // Check if already exists
        if await isFavorite(location) {
            throw FavoriteLocationsError.locationAlreadyExists
        }
        
        // Check storage limit
        let currentCount = try await getFavoriteLocations().count
        if currentCount >= maxFavorites {
            throw FavoriteLocationsError.storageLimit
        }
        
        // Create a copy and mark as favorite
        let favoriteLocation = location.asFavorite()
        
        do {
            // Insert into Core Data
            context.insert(favoriteLocation)
            try context.save()
            
            // Update local array
            await MainActor.run {
                self.favoriteLocations.append(favoriteLocation)
                self.favoriteLocations.sort { $0.displayName < $1.displayName }
            }
            
        } catch {
            throw FavoriteLocationsError.persistenceError(error)
        }
    }
    
    func removeFromFavorites(_ location: Location) async throws {
        guard let context = modelContext else {
            throw FavoriteLocationsError.persistenceError(NSError(domain: "ModelContext", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model context not available"]))
        }
        
        // Fetch all locations and filter manually
        let descriptor = FetchDescriptor<Location>()
        
        do {
            let allLocations = try context.fetch(descriptor)
            let favoriteLocations = allLocations.filter { $0.isFavorite }
            
            // Find the matching location by name and coordinates
            guard let foundLocation = favoriteLocations.first(where: { loc in
                loc.name == location.name &&
                abs(loc.latitude - location.latitude) < 0.001 &&
                abs(loc.longitude - location.longitude) < 0.001
            }) else {
                throw FavoriteLocationsError.locationNotFound
            }
            
            // Delete from Core Data
            context.delete(foundLocation)
            try context.save()
            
            // Update local array
            await MainActor.run {
                self.favoriteLocations.removeAll { $0.id == foundLocation.id }
            }
            
        } catch {
            if error is FavoriteLocationsError {
                throw error
            } else {
                throw FavoriteLocationsError.persistenceError(error)
            }
        }
    }
    
    func getFavoriteLocations() async throws -> [Location] {
        guard let context = modelContext else {
            throw FavoriteLocationsError.persistenceError(NSError(domain: "ModelContext", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model context not available"]))
        }
        
        // Fetch all locations and filter favorites manually
        let descriptor = FetchDescriptor<Location>(
            sortBy: [SortDescriptor(\.name)]
        )
        
        do {
            let allLocations = try context.fetch(descriptor)
            let favoriteLocations = allLocations.filter { $0.isFavorite }
            
            // Validate all locations
            try favoriteLocations.validateAll()
            
            return favoriteLocations
        } catch {
            throw FavoriteLocationsError.persistenceError(error)
        }
    }
    
    func isFavorite(_ location: Location) async -> Bool {
        do {
            let favorites = try await getFavoriteLocations()
            return favorites.contains { favorite in
                // Check if coordinates and name match (allowing for small coordinate differences)
                abs(favorite.latitude - location.latitude) < 0.001 &&
                abs(favorite.longitude - location.longitude) < 0.001 &&
                favorite.name == location.name
            }
        } catch {
            return false
        }
    }
    
    func updateFavoriteLocation(_ location: Location) async throws {
        guard let context = modelContext else {
            throw FavoriteLocationsError.persistenceError(NSError(domain: "ModelContext", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model context not available"]))
        }
        
        // Validate location
        try location.validate()
        
        // Fetch all locations and filter manually
        let descriptor = FetchDescriptor<Location>()
        
        do {
            let allLocations = try context.fetch(descriptor)
            let favoriteLocations = allLocations.filter { $0.isFavorite }
            
            // Find the matching location by ID
            guard let foundLocation = favoriteLocations.first(where: { $0.id == location.id }) else {
                throw FavoriteLocationsError.locationNotFound
            }
            
            // Update the location
            foundLocation.name = location.name
            foundLocation.city = location.city
            foundLocation.country = location.country
            foundLocation.latitude = location.latitude
            foundLocation.longitude = location.longitude
            foundLocation.diyanetId = location.diyanetId
            foundLocation.lastUpdated = Date()
            
            try context.save()
            
            // Update local array
            await loadFavorites()
            
        } catch {
            if error is FavoriteLocationsError {
                throw error
            } else {
                throw FavoriteLocationsError.persistenceError(error)
            }
        }
    }
    
    func clearAllFavorites() async throws {
        guard let context = modelContext else {
            throw FavoriteLocationsError.persistenceError(NSError(domain: "ModelContext", code: 0, userInfo: [NSLocalizedDescriptionKey: "Model context not available"]))
        }
        
        let descriptor = FetchDescriptor<Location>()
        
        do {
            let allLocations = try context.fetch(descriptor)
            let favoriteLocations = allLocations.filter { $0.isFavorite }
            
            for location in favoriteLocations {
                context.delete(location)
            }
            
            try context.save()
            
            // Clear local array
            await MainActor.run {
                self.favoriteLocations.removeAll()
            }
            
        } catch {
            throw FavoriteLocationsError.persistenceError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadFavorites() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let favorites = try await getFavoriteLocations()
            
            await MainActor.run {
                self.favoriteLocations = favorites
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Utility Methods
    
    /// Get favorite locations sorted by distance from a reference location
    func getFavoriteLocationsSortedByDistance(from referenceLocation: Location) async throws -> [Location] {
        let favorites = try await getFavoriteLocations()
        
        return favorites.sorted { location1, location2 in
            let distance1 = referenceLocation.distance(from: location1)
            let distance2 = referenceLocation.distance(from: location2)
            return distance1 < distance2
        }
    }
    
    /// Search within favorite locations
    func searchFavorites(query: String) async throws -> [Location] {
        let favorites = try await getFavoriteLocations()
        
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return favorites
        }
        
        let lowercaseQuery = query.lowercased()
        
        return favorites.filter { location in
            location.name.lowercased().contains(lowercaseQuery) ||
            location.city.lowercased().contains(lowercaseQuery) ||
            location.country.lowercased().contains(lowercaseQuery)
        }
    }
    
    /// Get statistics about favorite locations
    func getFavoritesStatistics() async throws -> FavoritesStatistics {
        let favorites = try await getFavoriteLocations()
        
        let countries = Set(favorites.map { $0.country })
        let cities = Set(favorites.map { $0.city })
        let withDiyanetId = favorites.filter { $0.diyanetId != nil }
        
        return FavoritesStatistics(
            totalCount: favorites.count,
            countriesCount: countries.count,
            citiesCount: cities.count,
            withDiyanetIdCount: withDiyanetId.count,
            maxAllowed: maxFavorites
        )
    }
    
    /// Check if we can add more favorites
    var canAddMoreFavorites: Bool {
        return favoriteLocations.count < maxFavorites
    }
    
    /// Get remaining favorite slots
    var remainingFavoriteSlots: Int {
        return max(0, maxFavorites - favoriteLocations.count)
    }
}

// MARK: - Favorites Statistics

struct FavoritesStatistics {
    let totalCount: Int
    let countriesCount: Int
    let citiesCount: Int
    let withDiyanetIdCount: Int
    let maxAllowed: Int
    
    var utilizationPercentage: Double {
        guard maxAllowed > 0 else { return 0 }
        return Double(totalCount) / Double(maxAllowed) * 100
    }
    
    var canAddMore: Bool {
        return totalCount < maxAllowed
    }
    
    var remainingSlots: Int {
        return max(0, maxAllowed - totalCount)
    }
}

// MARK: - Location Extensions for Favorites

extension Location {
    /// Create a favorite location from a regular location
    func asFavorite() -> Location {
        do {
            return try Location(
                id: self.id,
                name: self.name,
                city: self.city,
                country: self.country,
                latitude: self.latitude,
                longitude: self.longitude,
                diyanetId: self.diyanetId,
                isFavorite: true,
                isGPSLocation: false
            )
        } catch {
            // Fallback - this shouldn't happen with valid data
            return self
        }
    }
    
    /// Create a non-favorite location from a favorite
    func asRegular() -> Location {
        do {
            return try Location(
                id: self.id,
                name: self.name,
                city: self.city,
                country: self.country,
                latitude: self.latitude,
                longitude: self.longitude,
                diyanetId: self.diyanetId,
                isFavorite: false,
                isGPSLocation: self.isGPSLocation
            )
        } catch {
            // Fallback - this shouldn't happen with valid data
            return self
        }
    }
    
    /// Check if this location matches another location (for duplicate detection)
    func matches(_ other: Location) -> Bool {
        // Consider locations matching if they have similar coordinates and same name
        let coordinateThreshold = 0.001 // About 100 meters
        
        return abs(self.latitude - other.latitude) < coordinateThreshold &&
               abs(self.longitude - other.longitude) < coordinateThreshold &&
               self.name.lowercased() == other.name.lowercased()
    }
}