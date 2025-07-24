//
//  DiyanetAPIModels.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation

// MARK: - API Request Models

struct DailyPrayerTimesRequest {
    let locationId: String
    let date: String? // ISO date string (YYYY-MM-DD)
    let method: String? // calculation method
    
    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "locationId", value: locationId)]
        
        if let date = date {
            items.append(URLQueryItem(name: "date", value: date))
        }
        
        if let method = method {
            items.append(URLQueryItem(name: "method", value: method))
        }
        
        return items
    }
}

struct AnnualPrayerTimesRequest {
    let locationId: String
    let year: Int?
    
    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "locationId", value: locationId)]
        
        if let year = year {
            items.append(URLQueryItem(name: "year", value: String(year)))
        }
        
        return items
    }
}

struct LocationSearchRequest {
    let query: String
    let limit: Int?
    
    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "query", value: query)]
        
        if let limit = limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        
        return items
    }
}

struct ReverseGeocodeRequest: Codable {
    let latitude: Double
    let longitude: Double
}

// MARK: - API Response Models

struct PrayerTimeResponse: Codable {
    let type: String
    let time: String // ISO datetime string
    let completed: Bool?
}

struct DailyPrayerScheduleResponse: Codable {
    let id: String
    let locationId: String
    let locationName: String
    let city: String
    let country: String
    let region: String?
    let date: String // ISO date string
    let prayers: [PrayerTimeResponse]
    let calculationMethod: String
}

struct SimpleDailyPrayerScheduleResponse: Codable {
    let id: String
    let date: String // ISO date string
    let prayers: [PrayerTimeResponse]
}

struct AnnualPrayerDataResponse: Codable {
    let locationId: String
    let locationName: String
    let city: String
    let country: String
    let region: String?
    let year: Int
    let schedules: [SimpleDailyPrayerScheduleResponse]
    let calculationMethod: String
}

struct LocationSearchResultResponse: Codable {
    let id: String?
    let name: String
    let country: String
    let region: String?
    let diyanetId: Int?
    let coordinates: CoordinatesResponse?
}

struct LocationSearchResponse: Codable {
    let results: [LocationSearchResultResponse]
    let total: Int
    let query: String
}

struct CoordinatesResponse: Codable {
    let latitude: Double
    let longitude: Double
}

struct LocationDataResponse: Codable {
    let id: String?
    let name: String
    let city: String?
    let region: String?
    let latitude: Double
    let longitude: Double
    let country: String
    let diyanetId: Int?
    let timezone: String
}

// MARK: - Error Response Models

struct APIErrorResponse: Codable {
    let error: APIErrorDetail
    let timestamp: String
    let path: String
}

struct APIErrorDetail: Codable {
    let code: String
    let message: String
    let details: AnyCodable?
}

// Helper for decoding arbitrary JSON
struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T?) {
        self.value = value ?? ()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            value = ()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is Void:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Cannot encode value"))
        }
    }
}

// MARK: - Model Extensions for Conversion

extension PrayerTimeResponse {
    func toPrayerType() -> PrayerType? {
        return PrayerType(rawValue: type)
    }
    
    func toDate() -> Date? {
        // Strip timezone info and parse as local time
        let cleanTime = time.replacingOccurrences(of: "Z$", with: "", options: .regularExpression)
                           .replacingOccurrences(of: "[+-]\\d{2}:\\d{2}$", with: "", options: .regularExpression)
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        // Try with milliseconds first
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let date = formatter.date(from: cleanTime) {
            return date
        }
        
        // Try without milliseconds
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: cleanTime)
    }
}

extension DailyPrayerScheduleResponse {
    func toDate() -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
    
    func toPrayers() throws -> [Prayer] {
        guard toDate() != nil else {
            throw DiyanetAPIError.invalidDateFormat
        }
        
        let locationUUID = UUID() // This will need to be mapped properly
        
        var result: [Prayer] = []
        for prayerResponse in prayers {
            guard let prayerType = prayerResponse.toPrayerType(),
                  let prayerTime = prayerResponse.toDate() else {
                continue
            }
            
            let prayer = try Prayer(
                prayerType: prayerType,
                time: prayerTime,
                locationId: locationUUID,
                isCompleted: prayerResponse.completed ?? false
            )
            result.append(prayer)
        }
        
        return result
    }
}

extension AnnualPrayerDataResponse {
    func toPrayers() throws -> [Prayer] {
        let locationUUID = UUID() // This will need to be mapped properly
        var allPrayers: [Prayer] = []
        
        for schedule in schedules {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard formatter.date(from: schedule.date) != nil else {
                continue
            }
            
            for prayerResponse in schedule.prayers {
                guard let prayerType = prayerResponse.toPrayerType(),
                      let prayerTime = prayerResponse.toDate() else {
                    continue
                }
                
                let prayer = try Prayer(
                    prayerType: prayerType,
                    time: prayerTime,
                    locationId: locationUUID,
                    isCompleted: prayerResponse.completed ?? false
                )
                allPrayers.append(prayer)
            }
        }
        
        return allPrayers
    }
}

extension LocationSearchResultResponse {
    func toLocation() throws -> Location {
        // Use default coordinates if not provided (will be updated when needed)
        let lat = coordinates?.latitude ?? 0.0
        let lon = coordinates?.longitude ?? 0.0
        
        print("🔄 Converting LocationSearchResultResponse to Location:")
        print("   name: \(name)")
        print("   region: \(region ?? "nil")")
        print("   country: \(country)")
        print("   diyanetId: \(diyanetId?.description ?? "nil")")
        print("   coordinates: lat=\(lat), lon=\(lon)")
        
        // For search results, we'll create a location even without valid coordinates
        // The coordinates will be fetched later if needed
        
        do {
            let location = try Location(
                name: name,
                city: region ?? name, // Use region as city if available, otherwise use name
                country: country,
                latitude: lat,
                longitude: lon,
                diyanetId: diyanetId != nil ? String(diyanetId!) : nil,
                isFavorite: false,
                isGPSLocation: false
            )
            print("✅ Successfully created Location: \(location.displayName)")
            return location
        } catch {
            print("❌ Failed to create Location: \(error)")
            throw error
        }
    }
}

extension LocationDataResponse {
    func toLocation() throws -> Location {
        // Validate coordinates
        try Location.validateCoordinates(latitude: latitude, longitude: longitude)
        
        return try Location(
            name: name,
            city: city ?? name, // Use name as city if city is not available
            country: country,
            latitude: latitude,
            longitude: longitude,
            diyanetId: diyanetId != nil ? String(diyanetId!) : nil,
            isFavorite: false,
            isGPSLocation: false
        )
    }
}