//
//  SessionManager.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Session State

struct SessionState: Codable {
    let selectedLocationId: UUID?
    let useGPSLocation: Bool
    let lastSelectedLocationName: String?
    let lastSelectedLocationCoordinates: (latitude: Double, longitude: Double)?
    let sidebarExpanded: Bool
    let windowFrame: CGRect?
    let lastActiveDate: Date
    let appVersion: String
    
    enum CodingKeys: String, CodingKey {
        case selectedLocationId
        case useGPSLocation
        case lastSelectedLocationName
        case lastSelectedLocationLatitude
        case lastSelectedLocationLongitude
        case sidebarExpanded
        case windowFrameX
        case windowFrameY
        case windowFrameWidth
        case windowFrameHeight
        case lastActiveDate
        case appVersion
    }
    
    init(selectedLocationId: UUID? = nil,
         useGPSLocation: Bool = true,
         lastSelectedLocationName: String? = nil,
         lastSelectedLocationCoordinates: (latitude: Double, longitude: Double)? = nil,
         sidebarExpanded: Bool = true,
         windowFrame: CGRect? = nil,
         lastActiveDate: Date = Date(),
         appVersion: String = Bundle.main.appVersion) {
        self.selectedLocationId = selectedLocationId
        self.useGPSLocation = useGPSLocation
        self.lastSelectedLocationName = lastSelectedLocationName
        self.lastSelectedLocationCoordinates = lastSelectedLocationCoordinates
        self.sidebarExpanded = sidebarExpanded
        self.windowFrame = windowFrame
        self.lastActiveDate = lastActiveDate
        self.appVersion = appVersion
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedLocationId, forKey: .selectedLocationId)
        try container.encode(useGPSLocation, forKey: .useGPSLocation)
        try container.encodeIfPresent(lastSelectedLocationName, forKey: .lastSelectedLocationName)
        try container.encodeIfPresent(lastSelectedLocationCoordinates?.latitude, forKey: .lastSelectedLocationLatitude)
        try container.encodeIfPresent(lastSelectedLocationCoordinates?.longitude, forKey: .lastSelectedLocationLongitude)
        try container.encode(sidebarExpanded, forKey: .sidebarExpanded)
        try container.encodeIfPresent(windowFrame?.origin.x, forKey: .windowFrameX)
        try container.encodeIfPresent(windowFrame?.origin.y, forKey: .windowFrameY)
        try container.encodeIfPresent(windowFrame?.size.width, forKey: .windowFrameWidth)
        try container.encodeIfPresent(windowFrame?.size.height, forKey: .windowFrameHeight)
        try container.encode(lastActiveDate, forKey: .lastActiveDate)
        try container.encode(appVersion, forKey: .appVersion)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedLocationId = try container.decodeIfPresent(UUID.self, forKey: .selectedLocationId)
        useGPSLocation = try container.decode(Bool.self, forKey: .useGPSLocation)
        lastSelectedLocationName = try container.decodeIfPresent(String.self, forKey: .lastSelectedLocationName)
        
        let latitude = try container.decodeIfPresent(Double.self, forKey: .lastSelectedLocationLatitude)
        let longitude = try container.decodeIfPresent(Double.self, forKey: .lastSelectedLocationLongitude)
        if let lat = latitude, let lon = longitude {
            lastSelectedLocationCoordinates = (latitude: lat, longitude: lon)
        } else {
            lastSelectedLocationCoordinates = nil
        }
        
        sidebarExpanded = try container.decodeIfPresent(Bool.self, forKey: .sidebarExpanded) ?? true
        
        let x = try container.decodeIfPresent(CGFloat.self, forKey: .windowFrameX)
        let y = try container.decodeIfPresent(CGFloat.self, forKey: .windowFrameY)
        let width = try container.decodeIfPresent(CGFloat.self, forKey: .windowFrameWidth)
        let height = try container.decodeIfPresent(CGFloat.self, forKey: .windowFrameHeight)
        
        if let x = x, let y = y, let width = width, let height = height {
            windowFrame = CGRect(x: x, y: y, width: width, height: height)
        } else {
            windowFrame = nil
        }
        
        lastActiveDate = try container.decode(Date.self, forKey: .lastActiveDate)
        appVersion = try container.decode(String.self, forKey: .appVersion)
    }
}

// MARK: - Session Manager

class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    private let userDefaults = UserDefaults.standard
    private let sessionStateKey = "SessionState"
    
    // Current session state
    var currentState: SessionState
    
    // Observable properties for UI binding
    @Published var selectedLocationId: UUID? {
        didSet {
            updateSessionState()
        }
    }
    
    @Published var useGPSLocation: Bool {
        didSet {
            updateSessionState()
        }
    }
    
    @Published var sidebarExpanded: Bool {
        didSet {
            updateSessionState()
        }
    }
    
    @Published var windowFrame: CGRect? {
        didSet {
            updateSessionState()
        }
    }
    
    private init() {
        // Load saved session state or create default
        if let data = userDefaults.data(forKey: sessionStateKey),
           let savedState = try? JSONDecoder().decode(SessionState.self, from: data) {
            self.currentState = savedState
        } else {
            self.currentState = SessionState()
        }
        
        // Initialize observable properties from saved state
        self.selectedLocationId = self.currentState.selectedLocationId
        self.useGPSLocation = self.currentState.useGPSLocation
        self.sidebarExpanded = self.currentState.sidebarExpanded
        self.windowFrame = self.currentState.windowFrame
    }
    
    // MARK: - Session Management
    
    /// Save current session state
    func saveSession() {
        updateSessionState()
        persistSessionState()
    }
    
    /// Restore session state to UI components
    func restoreSession() {
        // Update PreferencesManager with session state
        let preferencesManager = PreferencesManager.shared
        preferencesManager.selectedLocationId = currentState.selectedLocationId
        preferencesManager.useGPSLocation = currentState.useGPSLocation
        
        // Post notification for UI components to restore state
        NotificationCenter.default.post(
            name: Notification.Name("SessionStateRestored"),
            object: nil,
            userInfo: [
                "sessionState": currentState
            ]
        )
    }
    
    /// Update location selection in session
    func updateSelectedLocation(_ location: Location?) {
        if let location = location {
            selectedLocationId = location.id
            useGPSLocation = location.isGPSLocation
            
            // Update current state with location details
            currentState = SessionState(
                selectedLocationId: location.id,
                useGPSLocation: location.isGPSLocation,
                lastSelectedLocationName: location.name,
                lastSelectedLocationCoordinates: (latitude: location.latitude, longitude: location.longitude),
                sidebarExpanded: currentState.sidebarExpanded,
                windowFrame: currentState.windowFrame,
                lastActiveDate: Date(),
                appVersion: currentState.appVersion
            )
        } else {
            selectedLocationId = nil
            useGPSLocation = true
            
            // Update current state
            currentState = SessionState(
                selectedLocationId: nil,
                useGPSLocation: true,
                lastSelectedLocationName: nil,
                lastSelectedLocationCoordinates: nil,
                sidebarExpanded: currentState.sidebarExpanded,
                windowFrame: currentState.windowFrame,
                lastActiveDate: Date(),
                appVersion: currentState.appVersion
            )
        }
        
        persistSessionState()
    }
    
    /// Update window frame in session
    func updateWindowFrame(_ frame: CGRect) {
        windowFrame = frame
    }
    
    /// Update sidebar state in session
    func updateSidebarState(expanded: Bool) {
        sidebarExpanded = expanded
    }
    
    /// Get the last selected location for restoration
    func getLastSelectedLocationInfo() -> (id: UUID?, name: String?, coordinates: (latitude: Double, longitude: Double)?, useGPS: Bool) {
        return (
            id: currentState.selectedLocationId,
            name: currentState.lastSelectedLocationName,
            coordinates: currentState.lastSelectedLocationCoordinates,
            useGPS: currentState.useGPSLocation
        )
    }
    
    /// Check if this is a fresh app launch (no previous session)
    var isFreshLaunch: Bool {
        return userDefaults.data(forKey: sessionStateKey) == nil
    }
    
    /// Check if app version has changed since last session
    var hasAppVersionChanged: Bool {
        return currentState.appVersion != Bundle.main.appVersion
    }
    
    /// Get time since last active session
    var timeSinceLastActive: TimeInterval {
        return Date().timeIntervalSince(currentState.lastActiveDate)
    }
    
    /// Check if session is stale (older than 24 hours)
    var isSessionStale: Bool {
        return timeSinceLastActive > 24 * 60 * 60
    }
    
    // MARK: - Private Methods
    
    private func updateSessionState() {
        currentState = SessionState(
            selectedLocationId: selectedLocationId,
            useGPSLocation: useGPSLocation,
            lastSelectedLocationName: currentState.lastSelectedLocationName,
            lastSelectedLocationCoordinates: currentState.lastSelectedLocationCoordinates,
            sidebarExpanded: sidebarExpanded,
            windowFrame: windowFrame,
            lastActiveDate: Date(),
            appVersion: Bundle.main.appVersion
        )
    }
    
    private func persistSessionState() {
        do {
            let data = try JSONEncoder().encode(currentState)
            userDefaults.set(data, forKey: sessionStateKey)
        } catch {
            print("Failed to save session state: \(error)")
        }
    }
    
    // MARK: - Session Restoration Helpers
    
    /// Attempt to restore the last selected location from favorites
    func restoreLastSelectedLocation(in context: ModelContext) async -> Location? {
        guard let locationId = currentState.selectedLocationId else {
            return nil
        }
        
        // Try to find the location in favorites
        do {
            let descriptor = FetchDescriptor<Location>(
                predicate: #Predicate { location in
                    location.id == locationId
                }
            )
            
            if let location = try context.fetch(descriptor).first {
                return location
            }
            
            // If location not found by ID, try to find by name and coordinates
            if let name = currentState.lastSelectedLocationName,
               let coordinates = currentState.lastSelectedLocationCoordinates {
                
                let nameDescriptor = FetchDescriptor<Location>(
                    predicate: #Predicate { location in
                        location.name == name
                    }
                )
                
                let locationsByName = try context.fetch(nameDescriptor)
                
                // Filter by coordinates manually since abs() is not supported in predicates
                return locationsByName.first { location in
                    abs(location.latitude - coordinates.latitude) < 0.001 &&
                    abs(location.longitude - coordinates.longitude) < 0.001
                }
            }
            
        } catch {
            print("Failed to restore last selected location: \(error)")
        }
        
        return nil
    }
    
    /// Clear session state (for reset scenarios)
    func clearSession() {
        userDefaults.removeObject(forKey: sessionStateKey)
        currentState = SessionState()
        selectedLocationId = nil
        useGPSLocation = true
        sidebarExpanded = true
        windowFrame = nil
    }
}

// MARK: - Bundle Extension for App Version

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var fullVersion: String {
        return "\(appVersion) (\(buildNumber))"
    }
}

