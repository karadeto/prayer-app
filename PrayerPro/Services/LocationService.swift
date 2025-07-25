//
//  LocationService.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import CoreLocation
import SwiftData

// MARK: - Location Errors

enum LocationError: LocalizedError {
    case permissionDenied
    case locationUnavailable
    case networkError
    case invalidCoordinates
    case geocodingFailed
    case searchFailed(String)
    case timeout
    case serviceDisabled
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission is required to get prayer times for your current location"
        case .locationUnavailable:
            return "Unable to determine your current location. Please check your location settings"
        case .networkError:
            return "Network connection error while searching for locations"
        case .invalidCoordinates:
            return "Invalid GPS coordinates received"
        case .geocodingFailed:
            return "Failed to find location information for your coordinates"
        case .searchFailed(let query):
            return "No locations found for '\(query)'"
        case .timeout:
            return "Location request timed out. Please try again"
        case .serviceDisabled:
            return "Location services are disabled. Please enable them in System Preferences"
        }
    }
}

// MARK: - Location Manager Protocol

protocol LocationServiceProtocol {
    func requestLocationPermission() async -> Bool
    func getCurrentLocation() async throws -> Location
    func searchLocations(query: String) async throws -> [Location]
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> Location
    var authorizationStatus: CLAuthorizationStatus { get }
    var isLocationServicesEnabled: Bool { get }
}

// MARK: - Location Manager Implementation

@MainActor
@Observable
class LocationService: NSObject, LocationServiceProtocol {
    static let shared = LocationService()
    
    private let locationManager = CLLocationManager()
    private let apiClient = DiyanetAPIClient.shared
    private var currentLocation: CLLocation?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var permissionContinuation: CheckedContinuation<Bool, Never>?
    
    // Location request timeout - reduced from 30s to 15s for better UX
    private let locationTimeout: TimeInterval = 15.0
    private var locationTimer: Timer?
    
    // Observable properties
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    var isLocationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        // Use reduced accuracy for faster GPS lock while still being precise enough for prayer times
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 500 // Update when moved 500 meters
    }
    
    // MARK: - Location Permission
    
    func requestLocationPermission() async -> Bool {
        // Check if location services are enabled
        guard CLLocationManager.locationServicesEnabled() else {
            return false
        }
        
        // Check current authorization status
        switch locationManager.authorizationStatus {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            // Request permission
            return await withCheckedContinuation { continuation in
                self.permissionContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways:
            return true
        @unknown default:
            return false
        }
    }
    
    // MARK: - Current Location
    
    func getCurrentLocation() async throws -> Location {
        // Check location services
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.serviceDisabled
        }
        
        // Check permission
        guard locationManager.authorizationStatus == .authorized || 
              locationManager.authorizationStatus == .authorizedAlways else {
            throw LocationError.permissionDenied
        }
        
        // Get current location with timeout
        let clLocation = try await getCurrentCLLocation()
        
        // Convert to our Location model using reverse geocoding
        return try await reverseGeocode(
            latitude: clLocation.coordinate.latitude,
            longitude: clLocation.coordinate.longitude
        )
    }
    
    private func getCurrentCLLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            // Ensure we don't have a pending continuation
            if let existingContinuation = self.locationContinuation {
                existingContinuation.resume(throwing: LocationError.locationUnavailable)
            }
            
            self.locationContinuation = continuation
            
            // Set up timeout timer
            self.locationTimer = Timer.scheduledTimer(withTimeInterval: locationTimeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if let cont = self.locationContinuation {
                    cont.resume(throwing: LocationError.timeout)
                    self.locationContinuation = nil
                    self.locationTimer?.invalidate()
                    self.locationTimer = nil
                }
            }
            
            // Check if location services are still enabled before requesting
            guard CLLocationManager.locationServicesEnabled() else {
                self.locationTimer?.invalidate()
                self.locationTimer = nil
                continuation.resume(throwing: LocationError.serviceDisabled)
                self.locationContinuation = nil
                return
            }
            
            // Check authorization status
            let status = locationManager.authorizationStatus
            guard status == .authorized || status == .authorizedAlways else {
                self.locationTimer?.invalidate()
                self.locationTimer = nil
                continuation.resume(throwing: LocationError.permissionDenied)
                self.locationContinuation = nil
                return
            }
            
            // Request location
            locationManager.requestLocation()
        }
    }
    
    // MARK: - Location Search
    
    func searchLocations(query: String) async throws -> [Location] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        do {
            let response = try await apiClient.searchLocations(query: query, limit: 20)
            
            var locations: [Location] = []
            for result in response.results {
                do {
                    let location = try result.toLocation()
                    locations.append(location)
                    print("✅ Successfully converted location: \(location.displayName)")
                } catch {
                    // Skip invalid locations but continue processing others
                    print("❌ Failed to convert location result: \(error)")
                    continue
                }
            }
            
            print("🔍 Successfully converted \(locations.count) out of \(response.results.count) search results")
            
            if locations.isEmpty {
                print("⚠️ No locations were successfully converted for query: '\(query)'")
                print("📊 API returned \(response.results.count) results")
                throw LocationError.searchFailed(query)
            }
            
            print("✅ Returning \(locations.count) successfully converted locations")
            return locations
        } catch {
            if error is DiyanetAPIError {
                throw LocationError.networkError
            } else {
                throw error
            }
        }
    }
    
    // MARK: - Reverse Geocoding
    
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> Location {
        // Validate coordinates
        guard latitude >= -90.0 && latitude <= 90.0 &&
              longitude >= -180.0 && longitude <= 180.0 else {
            throw LocationError.invalidCoordinates
        }
        
        do {
            let response = try await apiClient.reverseGeocode(
                latitude: latitude,
                longitude: longitude
            )
            
            let location = try response.toLocation()
            // Create a new location marked as GPS location
            return try Location(
                id: location.id,
                name: location.name,
                city: location.city,
                country: location.country,
                latitude: location.latitude,
                longitude: location.longitude,
                diyanetId: location.diyanetId,
                isFavorite: false,
                isGPSLocation: true
            )
            
        } catch {
            if error is DiyanetAPIError {
                throw LocationError.geocodingFailed
            } else {
                throw error
            }
        }
    }
    
    // MARK: - Utility Methods
    
    /// Check if we have valid location permission
    var hasLocationPermission: Bool {
        return authorizationStatus == .authorized || authorizationStatus == .authorizedAlways
    }
    
    /// Get the last known location without requesting a new one
    var lastKnownLocation: CLLocation? {
        return currentLocation
    }
    
    /// Calculate distance between two locations
    func distance(from location1: Location, to location2: Location) -> CLLocationDistance {
        return location1.distance(from: location2)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update current location
        currentLocation = location
        
        // Cancel timeout timer
        locationTimer?.invalidate()
        locationTimer = nil
        
        // Resume continuation if waiting
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Cancel timeout timer
        locationTimer?.invalidate()
        locationTimer = nil
        
        // Map Core Location errors to our errors
        let locationError: LocationError
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationError = .permissionDenied
            case .locationUnknown:
                locationError = .locationUnavailable
            case .network:
                locationError = .networkError
            default:
                locationError = .locationUnavailable
            }
        } else {
            locationError = .locationUnavailable
        }
        
        // Resume continuation with error
        locationContinuation?.resume(throwing: locationError)
        locationContinuation = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Resume permission continuation if waiting
        if let continuation = permissionContinuation {
            let hasPermission = status == .authorized || status == .authorizedAlways
            continuation.resume(returning: hasPermission)
            permissionContinuation = nil
        }
    }
}