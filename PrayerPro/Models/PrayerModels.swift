//
//  PrayerModels.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - Validation Errors
enum ValidationError: LocalizedError {
    case invalidCoordinates
    case invalidPrayerTime
    case invalidLocationName
    case invalidDiyanetId
    case invalidCompletionDate
    case missingRequiredField(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCoordinates:
            return "Invalid coordinates: latitude must be between -90 and 90, longitude between -180 and 180"
        case .invalidPrayerTime:
            return "Invalid prayer time: time cannot be in the future beyond 48 hours"
        case .invalidLocationName:
            return "Invalid location name: name cannot be empty"
        case .invalidDiyanetId:
            return "Invalid Diyanet ID: must be a valid numeric string"
        case .invalidCompletionDate:
            return "Invalid completion date: cannot be in the future"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        }
    }
}

// MARK: - Prayer Type Enum
enum PrayerType: String, CaseIterable, Codable {
    case fajr = "fajr"
    case sunrise = "sunrise"
    case dhuhr = "dhuhr"
    case asr = "asr"
    case maghrib = "maghrib"
    case isha = "isha"
    
    var displayName: String {
        switch self {
        case .fajr: return "Fajr"
        case .sunrise: return "Sunrise"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }
}

// MARK: - Prayer Model
@Model
final class Prayer: Codable {
    var id: UUID = UUID()
    var name: String = ""
    var time: Date = Date.now
    var locationId: UUID = UUID()
    var isCompleted: Bool = false
    var completedAt: Date? = nil
    var createdAt: Date = Date.now
    
    // Computed property for prayer type
    var prayerType: PrayerType {
        get { PrayerType(rawValue: name) ?? .fajr }
        set { name = newValue.rawValue }
    }
    
    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case id, name, time, locationId, isCompleted, completedAt, createdAt
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(time, forKey: .time)
        try container.encode(locationId, forKey: .locationId)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(createdAt, forKey: .createdAt)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.time = try container.decode(Date.self, forKey: .time)
        self.locationId = try container.decode(UUID.self, forKey: .locationId)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    init(id: UUID = UUID(), prayerType: PrayerType, time: Date, locationId: UUID, isCompleted: Bool = false, completedAt: Date? = nil) throws {
        // Validate prayer time
        try Self.validatePrayerTime(time)
        
        // Validate completion date if provided
        if let completedAt = completedAt {
            try Self.validateCompletionDate(completedAt)
        }
        
        self.id = id
        self.name = prayerType.rawValue
        self.time = time
        self.locationId = locationId
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = Date()
    }
    
    /// Internal initializer for annual data fetching that bypasses time validation
    internal init(uncheckedTime prayerType: PrayerType, time: Date, locationId: UUID, isCompleted: Bool = false, completedAt: Date? = nil) throws {
        // Only validate completion date if provided, skip prayer time validation for annual data
        if let completedAt = completedAt {
            try Self.validateCompletionDate(completedAt)
        }
        
        self.id = UUID()
        self.name = prayerType.rawValue
        self.time = time
        self.locationId = locationId
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = Date()
    }
    
    // MARK: - Validation Methods
    
    /// Validates that prayer time is reasonable (not more than 48 hours in the future, allows for next day prayers)
    static func validatePrayerTime(_ time: Date) throws {
        let now = Date()
        let maxFutureTime = now.addingTimeInterval(48 * 60 * 60) // 48 hours to allow next day prayers
        
        if time > maxFutureTime {
            throw ValidationError.invalidPrayerTime
        }
    }
    
    /// Validates completion date is not in the future
    static func validateCompletionDate(_ date: Date) throws {
        if date > Date() {
            throw ValidationError.invalidCompletionDate
        }
    }
    
    /// Validates the prayer instance
    func validate() throws {
        try Self.validatePrayerTime(self.time)
        
        if let completedAt = self.completedAt {
            try Self.validateCompletionDate(completedAt)
        }
        
        // Ensure completion logic is consistent
        if isCompleted && completedAt == nil {
            throw ValidationError.missingRequiredField("completedAt")
        }
        
        if !isCompleted && completedAt != nil {
            throw ValidationError.invalidCompletionDate
        }
    }
    
    /// Marks prayer as completed with validation
    func markCompleted() throws {
        let now = Date()
        try Self.validateCompletionDate(now)
        
        self.isCompleted = true
        self.completedAt = now
    }
    
    /// Marks prayer as not completed
    func markIncomplete() {
        self.isCompleted = false
        self.completedAt = nil
    }
}

// MARK: - Location Model
@Model
final class Location: Identifiable {
    var id: UUID = UUID()
    var name: String = "No Location"
    var city: String = "No City"
    var country: String = "No Country"
    var latitude: Double = 0
    var longitude: Double = 0
    var diyanetId: String? = nil
    var isFavorite: Bool = false
    var isGPSLocation: Bool = false
    var annualDataCached: Bool = false
    var lastUpdated: Date = Date.now
    
    // Computed property for CLLocationCoordinate2D
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Computed property for display name
    var displayName: String {
        return name
    }
    
    init(id: UUID = UUID(), name: String, city: String, country: String, latitude: Double, longitude: Double, diyanetId: String? = nil, isFavorite: Bool = false, isGPSLocation: Bool = false) throws {
        // Validate required fields
        try Self.validateLocationName(name)
        try Self.validateLocationName(city)
        try Self.validateLocationName(country)
        
        // Validate coordinates
        try Self.validateCoordinates(latitude: latitude, longitude: longitude)
        
        // Validate Diyanet ID if provided
        if let diyanetId = diyanetId {
            try Self.validateDiyanetId(diyanetId)
        }
        
        self.id = id
        self.name = name
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.diyanetId = diyanetId
        self.isFavorite = isFavorite
        self.isGPSLocation = isGPSLocation
        self.annualDataCached = false
        self.lastUpdated = Date()
    }
    
    // MARK: - Validation Methods
    
    /// Validates coordinates are within valid ranges
    static func validateCoordinates(latitude: Double, longitude: Double) throws {
        guard latitude >= -90.0 && latitude <= 90.0 else {
            throw ValidationError.invalidCoordinates
        }
        
        guard longitude >= -180.0 && longitude <= 180.0 else {
            throw ValidationError.invalidCoordinates
        }
    }
    
    /// Validates location name is not empty
    static func validateLocationName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidLocationName
        }
    }
    
    /// Validates Diyanet ID format (should be numeric)
    static func validateDiyanetId(_ id: String) throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty && trimmedId.allSatisfy({ $0.isNumber }) else {
            throw ValidationError.invalidDiyanetId
        }
    }
    
    /// Validates the location instance
    func validate() throws {
        try Self.validateLocationName(self.name)
        try Self.validateLocationName(self.city)
        try Self.validateLocationName(self.country)
        try Self.validateCoordinates(latitude: self.latitude, longitude: self.longitude)
        
        if let diyanetId = self.diyanetId {
            try Self.validateDiyanetId(diyanetId)
        }
    }
    
    /// Updates coordinates with validation
    func updateCoordinates(latitude: Double, longitude: Double) throws {
        try Self.validateCoordinates(latitude: latitude, longitude: longitude)
        self.latitude = latitude
        self.longitude = longitude
        self.lastUpdated = Date()
    }
    
    /// Updates location details with validation
    func updateDetails(name: String, city: String, country: String) throws {
        try Self.validateLocationName(name)
        try Self.validateLocationName(city)
        try Self.validateLocationName(country)
        
        self.name = name
        self.city = city
        self.country = country
        self.lastUpdated = Date()
    }
    
    /// Checks if coordinates are valid
    var hasValidCoordinates: Bool {
        do {
            try Self.validateCoordinates(latitude: latitude, longitude: longitude)
            return true
        } catch {
            return false
        }
    }
    
    /// Distance from another location in meters
    func distance(from other: Location) -> CLLocationDistance {
        let thisLocation = CLLocation(latitude: latitude, longitude: longitude)
        let otherLocation = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return thisLocation.distance(from: otherLocation)
    }
}

// MARK: - Prayer Completion Model
@Model
final class PrayerCompletion {
    var id: UUID = UUID()
    var prayerTypeName: String = ""
    var date: Date = Date.now
    var completedAt: Date = Date.now
    var locationId: UUID = UUID()
    var syncedToiCloud: Bool = false
    
    // Computed property for prayer type
    var prayerType: PrayerType {
        get { PrayerType(rawValue: prayerTypeName) ?? .fajr }
        set { prayerTypeName = newValue.rawValue }
    }
    
    init(id: UUID = UUID(), prayerType: PrayerType, date: Date, completedAt: Date = Date(), locationId: UUID, syncedToiCloud: Bool = false) throws {
        // Validate completion date
        try Self.validateCompletionDate(completedAt)
        
        // Validate that completion date is not before the prayer date
        try Self.validateCompletionLogic(prayerDate: date, completedAt: completedAt)
        
        self.id = id
        self.prayerTypeName = prayerType.rawValue
        self.date = date
        self.completedAt = completedAt
        self.locationId = locationId
        self.syncedToiCloud = syncedToiCloud
    }
    
    // MARK: - Validation Methods
    
    /// Validates completion date is not in the future
    static func validateCompletionDate(_ date: Date) throws {
        if date > Date() {
            throw ValidationError.invalidCompletionDate
        }
    }
    
    /// Validates that completion date makes sense relative to prayer date
    static func validateCompletionLogic(prayerDate: Date, completedAt: Date) throws {
        // Allow completion up to 24 hours after the prayer date
        let maxCompletionTime = prayerDate.addingTimeInterval(24 * 60 * 60)
        
        if completedAt > maxCompletionTime {
            throw ValidationError.invalidCompletionDate
        }
        
        // Don't allow completion more than 7 days before the prayer date
        let minCompletionTime = prayerDate.addingTimeInterval(-7 * 24 * 60 * 60)
        
        if completedAt < minCompletionTime {
            throw ValidationError.invalidCompletionDate
        }
    }
    
    /// Validates the prayer completion instance
    func validate() throws {
        try Self.validateCompletionDate(self.completedAt)
        try Self.validateCompletionLogic(prayerDate: self.date, completedAt: self.completedAt)
    }
    
    /// Marks as synced to iCloud
    func markSyncedToiCloud() {
        self.syncedToiCloud = true
    }
    
    /// Marks as not synced (for retry scenarios)
    func markNotSynced() {
        self.syncedToiCloud = false
    }
    
    /// Checks if this completion is for today
    var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }
    
    /// Checks if this completion is recent (within last 7 days)
    var isRecent: Bool {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return date >= sevenDaysAgo
    }
    
    /// Creates a completion record for a prayer
    static func createCompletion(for prayer: Prayer, at completionTime: Date = Date()) throws -> PrayerCompletion {
        return try PrayerCompletion(
            prayerType: prayer.prayerType,
            date: prayer.time,
            completedAt: completionTime,
            locationId: prayer.locationId
        )
    }
}

// MARK: - Prayer Status Helper
struct PrayerStatus {
    let currentPrayer: Prayer?
    let nextPrayer: Prayer?
    let timeUntilNext: TimeInterval
    let timeUntilCurrentEnds: TimeInterval
    let allPrayers: [Prayer]
    
    /// Validates that the prayer status is consistent
    func validate() throws {
        // Validate all prayers
        for prayer in allPrayers {
            try prayer.validate()
        }
        
        // Validate time until next is not negative (unless no next prayer)
        if nextPrayer != nil && timeUntilNext < 0 {
            throw ValidationError.invalidPrayerTime
        }
    }
}

// MARK: - Model Validation Extensions
extension Array where Element == Prayer {
    /// Validates all prayers in the array
    func validateAll() throws {
        for prayer in self {
            try prayer.validate()
        }
    }
    
    /// Sorts prayers by time
    func sortedByTime() -> [Prayer] {
        return self.sorted { $0.time < $1.time }
    }
    
    /// Filters prayers for a specific date
    func forDate(_ date: Date) -> [Prayer] {
        return self.filter { Calendar.current.isDate($0.time, inSameDayAs: date) }
    }
}

extension Array where Element == Location {
    /// Validates all locations in the array
    func validateAll() throws {
        for location in self {
            try location.validate()
        }
    }
    
    /// Filters favorite locations
    var favorites: [Location] {
        return self.filter { $0.isFavorite }
    }
    
    /// Filters GPS locations
    var gpsLocations: [Location] {
        return self.filter { $0.isGPSLocation }
    }
}

extension Array where Element == PrayerCompletion {
    /// Validates all prayer completions in the array
    func validateAll() throws {
        for completion in self {
            try completion.validate()
        }
    }
    
    /// Filters completions for a specific date
    func forDate(_ date: Date) -> [PrayerCompletion] {
        return self.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
    
    /// Filters unsynced completions
    var unsynced: [PrayerCompletion] {
        return self.filter { !$0.syncedToiCloud }
    }
    
    /// Filters recent completions (last 7 days)
    var recent: [PrayerCompletion] {
        return self.filter { $0.isRecent }
    }
}
