//
//  ErrorHandling.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftUI
import OSLog
import CoreLocation
import UserNotifications

// MARK: - Fallback Data Models

struct FallbackLocationData: Codable {
    let id: UUID
    let name: String
    let city: String
    let country: String
    let latitude: Double
    let longitude: Double
    let diyanetId: String?
    let isFavorite: Bool
    let isGPSLocation: Bool
}

// MARK: - Centralized Error Types

enum PrayerAppError: LocalizedError, Equatable {
    // Network and API Errors
    case networkUnavailable
    case apiTimeout
    case apiServerError(code: Int, message: String)
    case apiRateLimited
    case apiUnauthorized
    case apiNotFound
    case invalidAPIResponse
    
    // Location Errors
    case locationPermissionDenied
    case locationServicesDisabled
    case locationUnavailable
    case locationTimeout
    case invalidCoordinates
    case geocodingFailed
    
    // Notification Errors
    case notificationPermissionDenied
    case notificationSchedulingFailed
    case notificationSettingsUnavailable
    
    // Data and Storage Errors
    case dataCorruption
    case storageQuotaExceeded
    case iCloudSyncFailed
    case cacheCorrupted
    case migrationFailed
    
    // Prayer Time Errors
    case prayerTimesUnavailable
    case invalidPrayerData
    case calculationError
    
    // General Application Errors
    case unexpectedError(Error)
    case configurationError(String)
    case featureUnavailable(String)
    
    var errorDescription: String? {
        switch self {
        // Network and API Errors
        case .networkUnavailable:
            return "No internet connection available. Please check your network settings."
        case .apiTimeout:
            return "The request timed out. Please try again."
        case .apiServerError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .apiRateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .apiUnauthorized:
            return "Access denied. Please check your connection settings."
        case .apiNotFound:
            return "The requested resource was not found."
        case .invalidAPIResponse:
            return "Received invalid data from server. Please try again."
            
        // Location Errors
        case .locationPermissionDenied:
            return "Location permission is required to get prayer times for your current location."
        case .locationServicesDisabled:
            return "Location services are disabled. Please enable them in System Preferences."
        case .locationUnavailable:
            return "Unable to determine your current location. Please try again or select a location manually."
        case .locationTimeout:
            return "Location request timed out. Please try again."
        case .invalidCoordinates:
            return "Invalid GPS coordinates received."
        case .geocodingFailed:
            return "Failed to find location information for your coordinates."
            
        // Notification Errors
        case .notificationPermissionDenied:
            return "Notification permission is required for prayer time alerts."
        case .notificationSchedulingFailed:
            return "Failed to schedule prayer time notifications."
        case .notificationSettingsUnavailable:
            return "Unable to access notification settings."
            
        // Data and Storage Errors
        case .dataCorruption:
            return "Local data corruption detected. The app will reset its data."
        case .storageQuotaExceeded:
            return "Storage quota exceeded. Please free up some space."
        case .iCloudSyncFailed:
            return "Failed to sync with iCloud. Data will be stored locally."
        case .cacheCorrupted:
            return "Cache data is corrupted and will be refreshed."
        case .migrationFailed:
            return "Failed to migrate app data. Some data may be lost."
            
        // Prayer Time Errors
        case .prayerTimesUnavailable:
            return "Prayer times are currently unavailable. Please try again later."
        case .invalidPrayerData:
            return "Invalid prayer time data received."
        case .calculationError:
            return "Failed to calculate prayer times."
            
        // General Application Errors
        case .unexpectedError(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .featureUnavailable(let feature):
            return "\(feature) is currently unavailable."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        // Network and API Errors
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .apiTimeout:
            return "Check your internet connection and try again."
        case .apiServerError:
            return "The server is experiencing issues. Please try again later."
        case .apiRateLimited:
            return "Wait a few minutes before making another request."
        case .apiUnauthorized:
            return "Contact support if this problem persists."
        case .apiNotFound:
            return "Try searching for a different location."
        case .invalidAPIResponse:
            return "Try refreshing the data or restart the app."
            
        // Location Errors
        case .locationPermissionDenied:
            return "Go to System Preferences > Security & Privacy > Privacy > Location Services to enable location access."
        case .locationServicesDisabled:
            return "Go to System Preferences > Security & Privacy > Privacy > Location Services to enable location services."
        case .locationUnavailable:
            return "Try moving to an area with better GPS reception or select a location manually."
        case .locationTimeout:
            return "Try again or select a location manually from the search."
        case .invalidCoordinates, .geocodingFailed:
            return "Try again or select a location manually."
            
        // Notification Errors
        case .notificationPermissionDenied:
            return "Go to System Preferences > Notifications to enable notifications for PrayerPro."
        case .notificationSchedulingFailed:
            return "Try disabling and re-enabling notifications in the app preferences."
        case .notificationSettingsUnavailable:
            return "Restart the app and try again."
            
        // Data and Storage Errors
        case .dataCorruption:
            return "The app will automatically reset its data. Your favorites may need to be re-added."
        case .storageQuotaExceeded:
            return "Free up storage space on your device and try again."
        case .iCloudSyncFailed:
            return "Check your iCloud settings and internet connection."
        case .cacheCorrupted:
            return "The app will automatically refresh the data."
        case .migrationFailed:
            return "Some settings may need to be reconfigured."
            
        // Prayer Time Errors
        case .prayerTimesUnavailable:
            return "Try selecting a different location or check your internet connection."
        case .invalidPrayerData:
            return "Try refreshing the prayer times or select a different location."
        case .calculationError:
            return "Try selecting a different location or restart the app."
            
        // General Application Errors
        case .unexpectedError:
            return "Try restarting the app. Contact support if the problem persists."
        case .configurationError:
            return "Try restarting the app or reinstalling if the problem persists."
        case .featureUnavailable:
            return "This feature may be temporarily unavailable. Try again later."
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .networkUnavailable, .apiTimeout, .locationTimeout, .locationUnavailable:
            return .warning
        case .locationPermissionDenied, .notificationPermissionDenied, .locationServicesDisabled:
            return .warning
        case .dataCorruption, .migrationFailed, .storageQuotaExceeded:
            return .critical
        case .apiServerError, .iCloudSyncFailed, .cacheCorrupted:
            return .error
        case .prayerTimesUnavailable, .invalidPrayerData, .calculationError:
            return .error
        case .apiRateLimited, .notificationSchedulingFailed:
            return .warning
        case .unexpectedError, .configurationError:
            return .critical
        default:
            return .error
        }
    }
    
    var category: ErrorCategory {
        switch self {
        case .networkUnavailable, .apiTimeout, .apiServerError, .apiRateLimited, .apiUnauthorized, .apiNotFound, .invalidAPIResponse:
            return .network
        case .locationPermissionDenied, .locationServicesDisabled, .locationUnavailable, .locationTimeout, .invalidCoordinates, .geocodingFailed:
            return .location
        case .notificationPermissionDenied, .notificationSchedulingFailed, .notificationSettingsUnavailable:
            return .notifications
        case .dataCorruption, .storageQuotaExceeded, .iCloudSyncFailed, .cacheCorrupted, .migrationFailed:
            return .data
        case .prayerTimesUnavailable, .invalidPrayerData, .calculationError:
            return .prayerTimes
        case .unexpectedError, .configurationError, .featureUnavailable:
            return .system
        }
    }
    
    static func == (lhs: PrayerAppError, rhs: PrayerAppError) -> Bool {
        switch (lhs, rhs) {
        case (.networkUnavailable, .networkUnavailable),
             (.apiTimeout, .apiTimeout),
             (.apiRateLimited, .apiRateLimited),
             (.apiUnauthorized, .apiUnauthorized),
             (.apiNotFound, .apiNotFound),
             (.invalidAPIResponse, .invalidAPIResponse),
             (.locationPermissionDenied, .locationPermissionDenied),
             (.locationServicesDisabled, .locationServicesDisabled),
             (.locationUnavailable, .locationUnavailable),
             (.locationTimeout, .locationTimeout),
             (.invalidCoordinates, .invalidCoordinates),
             (.geocodingFailed, .geocodingFailed),
             (.notificationPermissionDenied, .notificationPermissionDenied),
             (.notificationSchedulingFailed, .notificationSchedulingFailed),
             (.notificationSettingsUnavailable, .notificationSettingsUnavailable),
             (.dataCorruption, .dataCorruption),
             (.storageQuotaExceeded, .storageQuotaExceeded),
             (.iCloudSyncFailed, .iCloudSyncFailed),
             (.cacheCorrupted, .cacheCorrupted),
             (.migrationFailed, .migrationFailed),
             (.prayerTimesUnavailable, .prayerTimesUnavailable),
             (.invalidPrayerData, .invalidPrayerData),
             (.calculationError, .calculationError):
            return true
        case (.apiServerError(let lCode, let lMessage), .apiServerError(let rCode, let rMessage)):
            return lCode == rCode && lMessage == rMessage
        case (.configurationError(let lMessage), .configurationError(let rMessage)):
            return lMessage == rMessage
        case (.featureUnavailable(let lFeature), .featureUnavailable(let rFeature)):
            return lFeature == rFeature
        default:
            return false
        }
    }
}

// MARK: - Error Classification

enum ErrorSeverity {
    case info
    case warning
    case error
    case critical
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return .purple
        }
    }
    
    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "exclamationmark.octagon"
        }
    }
}

enum ErrorCategory {
    case network
    case location
    case notifications
    case data
    case prayerTimes
    case system
    
    var displayName: String {
        switch self {
        case .network: return "Network"
        case .location: return "Location"
        case .notifications: return "Notifications"
        case .data: return "Data"
        case .prayerTimes: return "Prayer Times"
        case .system: return "System"
        }
    }
}

// MARK: - Error Context

struct ErrorContext {
    let error: PrayerAppError
    let timestamp: Date
    let userAction: String?
    let additionalInfo: [String: Any]?
    
    init(error: PrayerAppError, userAction: String? = nil, additionalInfo: [String: Any]? = nil) {
        self.error = error
        self.timestamp = Date()
        self.userAction = userAction
        self.additionalInfo = additionalInfo
    }
}

// MARK: - Error Recovery Actions

enum ErrorRecoveryAction {
    case retry
    case openSettings
    case openSystemPreferences
    case refreshData
    case selectManualLocation
    case contactSupport
    case dismiss
    case resetData
    
    var title: String {
        switch self {
        case .retry: return "Try Again"
        case .openSettings: return "Open Settings"
        case .openSystemPreferences: return "Open System Preferences"
        case .refreshData: return "Refresh Data"
        case .selectManualLocation: return "Select Location Manually"
        case .contactSupport: return "Contact Support"
        case .dismiss: return "Dismiss"
        case .resetData: return "Reset Data"
        }
    }
    
    var isDestructive: Bool {
        switch self {
        case .resetData: return true
        default: return false
        }
    }
}

// MARK: - Error Recovery Strategy

struct ErrorRecoveryStrategy {
    let primaryAction: ErrorRecoveryAction
    let secondaryActions: [ErrorRecoveryAction]
    let automaticRetry: Bool
    let retryDelay: TimeInterval?
    let maxRetries: Int
    
    static func strategy(for error: PrayerAppError) -> ErrorRecoveryStrategy {
        switch error {
        case .networkUnavailable, .apiTimeout:
            return ErrorRecoveryStrategy(
                primaryAction: .retry,
                secondaryActions: [.dismiss],
                automaticRetry: true,
                retryDelay: 5.0,
                maxRetries: 3
            )
            
        case .locationPermissionDenied:
            return ErrorRecoveryStrategy(
                primaryAction: .openSystemPreferences,
                secondaryActions: [.selectManualLocation, .dismiss],
                automaticRetry: false,
                retryDelay: nil,
                maxRetries: 0
            )
            
        case .locationServicesDisabled:
            return ErrorRecoveryStrategy(
                primaryAction: .openSystemPreferences,
                secondaryActions: [.selectManualLocation, .dismiss],
                automaticRetry: false,
                retryDelay: nil,
                maxRetries: 0
            )
            
        case .notificationPermissionDenied:
            return ErrorRecoveryStrategy(
                primaryAction: .openSystemPreferences,
                secondaryActions: [.dismiss],
                automaticRetry: false,
                retryDelay: nil,
                maxRetries: 0
            )
            
        case .dataCorruption:
            return ErrorRecoveryStrategy(
                primaryAction: .resetData,
                secondaryActions: [.contactSupport, .dismiss],
                automaticRetry: false,
                retryDelay: nil,
                maxRetries: 0
            )
            
        case .prayerTimesUnavailable, .invalidPrayerData:
            return ErrorRecoveryStrategy(
                primaryAction: .refreshData,
                secondaryActions: [.selectManualLocation, .dismiss],
                automaticRetry: true,
                retryDelay: 3.0,
                maxRetries: 2
            )
            
        case .iCloudSyncFailed:
            return ErrorRecoveryStrategy(
                primaryAction: .retry,
                secondaryActions: [.openSettings, .dismiss],
                automaticRetry: true,
                retryDelay: 10.0,
                maxRetries: 2
            )
            
        default:
            return ErrorRecoveryStrategy(
                primaryAction: .retry,
                secondaryActions: [.dismiss],
                automaticRetry: false,
                retryDelay: nil,
                maxRetries: 1
            )
        }
    }
}

// MARK: - Error Logger

class ErrorLogger {
    static let shared = ErrorLogger()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PrayerPro", category: "ErrorHandling")
    private let userDefaults = UserDefaults.standard
    private let maxLogEntries = 100
    private let logKey = "ErrorLog"
    
    private init() {}
    
    // MARK: - Logging Methods
    
    func log(_ error: PrayerAppError, context: ErrorContext? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let logEntry = ErrorLogEntry(
            error: error,
            context: context,
            file: URL(fileURLWithPath: file).lastPathComponent,
            function: function,
            line: line
        )
        
        // Log to system logger
        logToSystem(logEntry)
        
        // Store in local log
        storeLogEntry(logEntry)
        
        // Send to crash reporting if critical
        if error.severity == .critical {
            reportCriticalError(logEntry)
        }
    }
    
    func logNetworkError(_ error: Error, request: String? = nil) {
        let prayerError: PrayerAppError
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                prayerError = .apiTimeout
            case .notConnectedToInternet, .networkConnectionLost:
                prayerError = .networkUnavailable
            default:
                prayerError = .unexpectedError(error)
            }
        } else {
            prayerError = .unexpectedError(error)
        }
        
        let context = ErrorContext(
            error: prayerError,
            userAction: request,
            additionalInfo: ["originalError": error.localizedDescription]
        )
        
        log(prayerError, context: context)
    }
    
    func logLocationError(_ error: Error, action: String? = nil) {
        let prayerError: PrayerAppError
        
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                prayerError = .locationPermissionDenied
            case .locationUnknown:
                prayerError = .locationUnavailable
            case .network:
                prayerError = .networkUnavailable
            default:
                prayerError = .unexpectedError(error)
            }
        } else {
            prayerError = .unexpectedError(error)
        }
        
        let context = ErrorContext(
            error: prayerError,
            userAction: action,
            additionalInfo: ["originalError": error.localizedDescription]
        )
        
        log(prayerError, context: context)
    }
    
    // MARK: - System Logging
    
    private func logToSystem(_ entry: ErrorLogEntry) {
        let message = """
        Error: \(entry.error.localizedDescription ?? "Unknown error")
        Category: \(entry.error.category.displayName)
        Severity: \(entry.error.severity)
        Location: \(entry.file):\(entry.line) in \(entry.function)
        User Action: \(entry.context?.userAction ?? "None")
        """
        
        switch entry.error.severity {
        case .info:
            logger.info("\(message)")
        case .warning:
            logger.warning("\(message)")
        case .error:
            logger.error("\(message)")
        case .critical:
            logger.critical("\(message)")
        }
    }
    
    // MARK: - Local Storage
    
    private func storeLogEntry(_ entry: ErrorLogEntry) {
        var logs = getStoredLogs()
        logs.append(entry)
        
        // Keep only the most recent entries
        if logs.count > maxLogEntries {
            logs = Array(logs.suffix(maxLogEntries))
        }
        
        if let data = try? JSONEncoder().encode(logs) {
            userDefaults.set(data, forKey: logKey)
        }
    }
    
    private func getStoredLogs() -> [ErrorLogEntry] {
        guard let data = userDefaults.data(forKey: logKey),
              let logs = try? JSONDecoder().decode([ErrorLogEntry].self, from: data) else {
            return []
        }
        return logs
    }
    
    // MARK: - Critical Error Reporting
    
    private func reportCriticalError(_ entry: ErrorLogEntry) {
        // In a production app, this would send to crash reporting service
        // For now, we'll just log it prominently
        print("🚨 CRITICAL ERROR: \(entry.error.localizedDescription ?? "Unknown")")
        print("🚨 Context: \(entry.context?.userAction ?? "None")")
        print("🚨 Location: \(entry.file):\(entry.line)")
    }
    
    // MARK: - Log Retrieval
    
    func getRecentErrors(limit: Int = 20) -> [ErrorLogEntry] {
        let logs = getStoredLogs()
        return Array(logs.suffix(limit))
    }
    
    func getErrorsByCategory(_ category: ErrorCategory) -> [ErrorLogEntry] {
        return getStoredLogs().filter { $0.error.category == category }
    }
    
    func getErrorsBySeverity(_ severity: ErrorSeverity) -> [ErrorLogEntry] {
        return getStoredLogs().filter { $0.error.severity == severity }
    }
    
    func clearLogs() {
        userDefaults.removeObject(forKey: logKey)
    }
    
    // MARK: - Debug Export
    
    func exportLogsForDebug() -> String {
        let logs = getStoredLogs()
        var output = "PrayerPro Error Log Export\n"
        output += "Generated: \(Date())\n"
        output += "Total Entries: \(logs.count)\n\n"
        
        for (index, entry) in logs.enumerated() {
            output += "[\(index + 1)] \(entry.timestamp)\n"
            output += "Error: \(entry.error.localizedDescription ?? "Unknown")\n"
            output += "Category: \(entry.error.category.displayName)\n"
            output += "Severity: \(entry.error.severity)\n"
            output += "Location: \(entry.file):\(entry.line) in \(entry.function)\n"
            if let userAction = entry.context?.userAction {
                output += "User Action: \(userAction)\n"
            }
            output += "\n"
        }
        
        return output
    }
}

// MARK: - Error Log Entry

struct ErrorLogEntry: Codable {
    let id: UUID
    let error: PrayerAppError
    let context: ErrorContext?
    let timestamp: Date
    let file: String
    let function: String
    let line: Int
    
    init(error: PrayerAppError, context: ErrorContext?, file: String, function: String, line: Int) {
        self.id = UUID()
        self.error = error
        self.context = context
        self.timestamp = Date()
        self.file = file
        self.function = function
        self.line = line
    }
}

// Make ErrorContext Codable
extension ErrorContext: Codable {
    enum CodingKeys: String, CodingKey {
        case error, timestamp, userAction
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decode(PrayerAppError.self, forKey: .error)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        userAction = try container.decodeIfPresent(String.self, forKey: .userAction)
        additionalInfo = nil // Can't easily encode/decode [String: Any]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try error.encode(to: encoder)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(userAction, forKey: .userAction)
    }
}

// Make PrayerAppError Codable
extension PrayerAppError: Codable {
    enum CodingKeys: String, CodingKey {
        case type, code, message, underlyingError
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "networkUnavailable": self = .networkUnavailable
        case "apiTimeout": self = .apiTimeout
        case "apiRateLimited": self = .apiRateLimited
        case "apiUnauthorized": self = .apiUnauthorized
        case "apiNotFound": self = .apiNotFound
        case "invalidAPIResponse": self = .invalidAPIResponse
        case "locationPermissionDenied": self = .locationPermissionDenied
        case "locationServicesDisabled": self = .locationServicesDisabled
        case "locationUnavailable": self = .locationUnavailable
        case "locationTimeout": self = .locationTimeout
        case "invalidCoordinates": self = .invalidCoordinates
        case "geocodingFailed": self = .geocodingFailed
        case "notificationPermissionDenied": self = .notificationPermissionDenied
        case "notificationSchedulingFailed": self = .notificationSchedulingFailed
        case "notificationSettingsUnavailable": self = .notificationSettingsUnavailable
        case "dataCorruption": self = .dataCorruption
        case "storageQuotaExceeded": self = .storageQuotaExceeded
        case "iCloudSyncFailed": self = .iCloudSyncFailed
        case "cacheCorrupted": self = .cacheCorrupted
        case "migrationFailed": self = .migrationFailed
        case "prayerTimesUnavailable": self = .prayerTimesUnavailable
        case "invalidPrayerData": self = .invalidPrayerData
        case "calculationError": self = .calculationError
        case "apiServerError":
            let code = try container.decode(Int.self, forKey: .code)
            let message = try container.decode(String.self, forKey: .message)
            self = .apiServerError(code: code, message: message)
        case "configurationError":
            let message = try container.decode(String.self, forKey: .message)
            self = .configurationError(message)
        case "featureUnavailable":
            let message = try container.decode(String.self, forKey: .message)
            self = .featureUnavailable(message)
        case "unexpectedError":
            let errorMessage = try container.decode(String.self, forKey: .underlyingError)
            self = .unexpectedError(NSError(domain: "PrayerApp", code: 0, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown error type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .networkUnavailable:
            try container.encode("networkUnavailable", forKey: .type)
        case .apiTimeout:
            try container.encode("apiTimeout", forKey: .type)
        case .apiRateLimited:
            try container.encode("apiRateLimited", forKey: .type)
        case .apiUnauthorized:
            try container.encode("apiUnauthorized", forKey: .type)
        case .apiNotFound:
            try container.encode("apiNotFound", forKey: .type)
        case .invalidAPIResponse:
            try container.encode("invalidAPIResponse", forKey: .type)
        case .locationPermissionDenied:
            try container.encode("locationPermissionDenied", forKey: .type)
        case .locationServicesDisabled:
            try container.encode("locationServicesDisabled", forKey: .type)
        case .locationUnavailable:
            try container.encode("locationUnavailable", forKey: .type)
        case .locationTimeout:
            try container.encode("locationTimeout", forKey: .type)
        case .invalidCoordinates:
            try container.encode("invalidCoordinates", forKey: .type)
        case .geocodingFailed:
            try container.encode("geocodingFailed", forKey: .type)
        case .notificationPermissionDenied:
            try container.encode("notificationPermissionDenied", forKey: .type)
        case .notificationSchedulingFailed:
            try container.encode("notificationSchedulingFailed", forKey: .type)
        case .notificationSettingsUnavailable:
            try container.encode("notificationSettingsUnavailable", forKey: .type)
        case .dataCorruption:
            try container.encode("dataCorruption", forKey: .type)
        case .storageQuotaExceeded:
            try container.encode("storageQuotaExceeded", forKey: .type)
        case .iCloudSyncFailed:
            try container.encode("iCloudSyncFailed", forKey: .type)
        case .cacheCorrupted:
            try container.encode("cacheCorrupted", forKey: .type)
        case .migrationFailed:
            try container.encode("migrationFailed", forKey: .type)
        case .prayerTimesUnavailable:
            try container.encode("prayerTimesUnavailable", forKey: .type)
        case .invalidPrayerData:
            try container.encode("invalidPrayerData", forKey: .type)
        case .calculationError:
            try container.encode("calculationError", forKey: .type)
        case .apiServerError(let code, let message):
            try container.encode("apiServerError", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(message, forKey: .message)
        case .configurationError(let message):
            try container.encode("configurationError", forKey: .type)
            try container.encode(message, forKey: .message)
        case .featureUnavailable(let feature):
            try container.encode("featureUnavailable", forKey: .type)
            try container.encode(feature, forKey: .message)
        case .unexpectedError(let error):
            try container.encode("unexpectedError", forKey: .type)
            try container.encode(error.localizedDescription, forKey: .underlyingError)
        }
    }
}

// MARK: - Error Handler Manager

@MainActor
class ErrorHandlerManager: ObservableObject {
    static let shared = ErrorHandlerManager()
    
    private let logger = ErrorLogger.shared
    private var retryAttempts: [String: Int] = [:]
    private var activeRecoveryTasks: [String: Task<Void, Never>] = [:]
    
    // Published properties for UI
    @Published var currentError: PrayerAppError?
    @Published var isShowingError = false
    @Published var errorRecoveryStrategy: ErrorRecoveryStrategy?
    var isRecovering = false
    
    private init() {}
    
    // MARK: - Error Handling
    
    func handle(_ error: Error, context: String? = nil, showToUser: Bool = true) {
        let prayerError = mapToPrayerAppError(error)
        let errorContext = ErrorContext(error: prayerError, userAction: context)
        
        // Log the error
        logger.log(prayerError, context: errorContext)
        
        // Show to user if requested
        if showToUser {
            presentError(prayerError)
        }
        
        // Attempt automatic recovery if applicable
        attemptAutomaticRecovery(for: prayerError, context: context)
    }
    
    func handle(_ prayerError: PrayerAppError, context: String? = nil, showToUser: Bool = true) {
        let errorContext = ErrorContext(error: prayerError, userAction: context)
        
        // Log the error
        logger.log(prayerError, context: errorContext)
        
        // Show to user if requested
        if showToUser {
            presentError(prayerError)
        }
        
        // Attempt automatic recovery if applicable
        attemptAutomaticRecovery(for: prayerError, context: context)
    }
    
    private func mapToPrayerAppError(_ error: Error) -> PrayerAppError {
        // Map common system errors to our error types
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .apiTimeout
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkUnavailable
            default:
                return .unexpectedError(error)
            }
        }
        
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                return .locationPermissionDenied
            case .locationUnknown:
                return .locationUnavailable
            case .network:
                return .networkUnavailable
            default:
                return .unexpectedError(error)
            }
        }
        
        if let diyanetError = error as? DiyanetAPIError {
            switch diyanetError {
            case .noInternetConnection:
                return .networkUnavailable
            case .timeout:
                return .apiTimeout
            case .serverError(let code, let message):
                return .apiServerError(code: code, message: message)
            case .rateLimited, .tooManyRequests:
                return .apiRateLimited
            case .unauthorized:
                return .apiUnauthorized
            case .notFound:
                return .apiNotFound
            case .invalidResponse, .decodingError:
                return .invalidAPIResponse
            default:
                return .unexpectedError(error)
            }
        }
        
        if let locationError = error as? LocationError {
            switch locationError {
            case .permissionDenied:
                return .locationPermissionDenied
            case .serviceDisabled:
                return .locationServicesDisabled
            case .locationUnavailable:
                return .locationUnavailable
            case .timeout:
                return .locationTimeout
            case .invalidCoordinates:
                return .invalidCoordinates
            case .geocodingFailed:
                return .geocodingFailed
            case .networkError:
                return .networkUnavailable
            case .searchFailed:
                return .prayerTimesUnavailable
            }
        }
        
        return .unexpectedError(error)
    }
    
    // MARK: - Error Presentation
    
    private func presentError(_ error: PrayerAppError) {
        currentError = error
        errorRecoveryStrategy = ErrorRecoveryStrategy.strategy(for: error)
        isShowingError = true
    }
    
    func dismissError() {
        currentError = nil
        errorRecoveryStrategy = nil
        isShowingError = false
        isRecovering = false
    }
    
    // MARK: - Error Recovery
    
    func executeRecoveryAction(_ action: ErrorRecoveryAction) {
        guard let error = currentError else { return }
        
        switch action {
        case .retry:
            performRetry(for: error)
        case .openSettings:
            openAppSettings()
        case .openSystemPreferences:
            openSystemPreferences(for: error)
        case .refreshData:
            refreshData()
        case .selectManualLocation:
            showLocationSelection()
        case .contactSupport:
            contactSupport()
        case .resetData:
            resetAppData()
        case .dismiss:
            dismissError()
        }
    }
    
    private func performRetry(for error: PrayerAppError) {
        let errorKey = String(describing: error)
        let currentAttempts = retryAttempts[errorKey, default: 0]
        let strategy = ErrorRecoveryStrategy.strategy(for: error)
        
        guard currentAttempts < strategy.maxRetries else {
            // Max retries reached, show different options
            presentError(.featureUnavailable("Maximum retry attempts reached"))
            return
        }
        
        retryAttempts[errorKey] = currentAttempts + 1
        isRecovering = true
        
        // Post notification for retry attempt
        NotificationCenter.default.post(
            name: .errorRecoveryAttempt,
            object: nil,
            userInfo: ["error": error, "attempt": currentAttempts + 1]
        )
        
        // Dismiss current error during retry
        dismissError()
    }
    
    private func attemptAutomaticRecovery(for error: PrayerAppError, context: String?) {
        let strategy = ErrorRecoveryStrategy.strategy(for: error)
        
        guard strategy.automaticRetry,
              let delay = strategy.retryDelay else { return }
        
        let errorKey = String(describing: error)
        let currentAttempts = retryAttempts[errorKey, default: 0]
        
        guard currentAttempts < strategy.maxRetries else { return }
        
        // Cancel any existing recovery task for this error
        activeRecoveryTasks[errorKey]?.cancel()
        
        // Schedule automatic retry
        activeRecoveryTasks[errorKey] = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.performRetry(for: error)
            }
        }
    }
    
    // MARK: - Recovery Actions Implementation
    
    private func openAppSettings() {
        // Post notification to show app preferences
        NotificationCenter.default.post(name: .showAppPreferences, object: nil)
        dismissError()
    }
    
    private func openSystemPreferences(for error: PrayerAppError) {
        let url: URL?
        
        switch error.category {
        case .location:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
        case .notifications:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        default:
            url = URL(string: "x-apple.systempreferences:")
        }
        
        if let url = url {
            NSWorkspace.shared.open(url)
        }
        
        dismissError()
    }
    
    private func refreshData() {
        // Post notification to refresh all data
        NotificationCenter.default.post(name: .refreshAllData, object: nil)
        dismissError()
    }
    
    private func showLocationSelection() {
        // Post notification to show location search
        NotificationCenter.default.post(name: .showLocationSearch, object: nil)
        dismissError()
    }
    
    private func contactSupport() {
        // Generate debug information
        let debugInfo = generateDebugInfo()
        
        // Create email with debug info
        let emailBody = """
        Please describe the issue you're experiencing:
        
        
        
        --- Debug Information ---
        \(debugInfo)
        """
        
        let encodedBody = emailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mailtoURL = "mailto:support@prayerpro.app?subject=PrayerPro%20Support&body=\(encodedBody)"
        
        if let url = URL(string: mailtoURL) {
            NSWorkspace.shared.open(url)
        }
        
        dismissError()
    }
    
    private func resetAppData() {
        // Post notification to reset app data
        NotificationCenter.default.post(name: .resetAppData, object: nil)
        dismissError()
    }
    
    // MARK: - Debug Information
    
    private func generateDebugInfo() -> String {
        let recentErrors = logger.getRecentErrors(limit: 5)
        var info = """
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
        macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Date: \(Date())
        
        Recent Errors:
        """
        
        for (index, entry) in recentErrors.enumerated() {
            info += "\n\(index + 1). \(entry.error.localizedDescription ?? "Unknown") (\(entry.timestamp))"
        }
        
        return info
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Cancel all active recovery tasks
        for task in activeRecoveryTasks.values {
            task.cancel()
        }
        activeRecoveryTasks.removeAll()
        retryAttempts.removeAll()
    }
}

// MARK: - Graceful Degradation Manager

@MainActor
class GracefulDegradationManager: ObservableObject {
    static let shared = GracefulDegradationManager()
    
    // Feature availability states
    @Published var isNetworkAvailable = true
    @Published var isLocationAvailable = true
    @Published var isNotificationAvailable = true
    @Published var isiCloudAvailable = true
    @Published var isCacheAvailable = true
    
    // Network validation
    private var networkCheckCount = 0
    private var consecutiveFailures = 0
    private let requiredFailuresBeforeWarning = 3
    
    // Fallback data
    var fallbackPrayerTimes: [Prayer] = []
    var fallbackLocation: Location?
    var lastKnownGoodData: Date?
    
    private init() {
        setupNetworkMonitoring()
        loadFallbackData()
    }
    
    // MARK: - Feature Availability
    
    func updateFeatureAvailability() {
        // Check network with validation
        let currentNetworkStatus = NetworkOptimizer.shared.isConnected
        networkCheckCount += 1
        
        if currentNetworkStatus {
            // Network is available - reset failure counter
            consecutiveFailures = 0
            if !isNetworkAvailable {
                print("🌐 Network connection restored")
            }
            isNetworkAvailable = true
        } else {
            // Network appears unavailable - increment failure counter
            consecutiveFailures += 1
            print("🔍 Network check \(networkCheckCount): appears disconnected (failure \(consecutiveFailures)/\(requiredFailuresBeforeWarning))")
            
            // Only mark as unavailable after multiple consecutive failures
            if consecutiveFailures >= requiredFailuresBeforeWarning {
                if isNetworkAvailable {
                    print("⚠️ Network marked as unavailable after \(consecutiveFailures) consecutive checks")
                }
                isNetworkAvailable = false
            } else {
                // Still give benefit of doubt - keep as available
                print("🔍 Network check failed but keeping as available (need \(requiredFailuresBeforeWarning - consecutiveFailures) more failures)")
            }
        }
        
        // Check location services
        isLocationAvailable = CLLocationManager.locationServicesEnabled() && 
                             LocationService.shared.hasLocationPermission
        
        // Check notifications
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                self.isNotificationAvailable = settings.authorizationStatus == .authorized
            }
        }
        
        // Check iCloud (simplified check)
        isiCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        
        // Check cache availability
        checkCacheAvailability()
    }
    
    private func setupNetworkMonitoring() {
        // Monitor network changes
        NotificationCenter.default.addObserver(
            forName: .networkStatusChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.updateFeatureAvailability()
            }
        }
    }
    
    private func checkCacheAvailability() {
        // Check if cache is accessible and not corrupted
        do {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            isCacheAvailable = cacheURL != nil
        } catch {
            isCacheAvailable = false
        }
    }
    
    // MARK: - Fallback Data Management
    
    func storeFallbackData(prayers: [Prayer], location: Location) {
        fallbackPrayerTimes = prayers
        fallbackLocation = location
        lastKnownGoodData = Date()
        
        // Persist to UserDefaults as backup
        if let prayerData = try? JSONEncoder().encode(prayers) {
            let fallbackLocation = FallbackLocationData(
                id: location.id,
                name: location.name,
                city: location.city,
                country: location.country,
                latitude: location.latitude,
                longitude: location.longitude,
                diyanetId: location.diyanetId,
                isFavorite: location.isFavorite,
                isGPSLocation: location.isGPSLocation
            )
            if let locationData = try? JSONEncoder().encode(fallbackLocation) {
                UserDefaults.standard.set(prayerData, forKey: "FallbackPrayerTimes")
                UserDefaults.standard.set(locationData, forKey: "FallbackLocation")
                UserDefaults.standard.set(Date(), forKey: "LastKnownGoodData")
            }
        }
    }
    
    private func loadFallbackData() {
        if let prayerData = UserDefaults.standard.data(forKey: "FallbackPrayerTimes"),
           let prayers = try? JSONDecoder().decode([Prayer].self, from: prayerData) {
            fallbackPrayerTimes = prayers
        }
        
        if let locationData = UserDefaults.standard.data(forKey: "FallbackLocation"),
           let fallbackLocationData = try? JSONDecoder().decode(FallbackLocationData.self, from: locationData) {
            // Convert back to Location - this won't work with SwiftData model, so we'll just skip fallback location for now
            // fallbackLocation = location
        }
        
        lastKnownGoodData = UserDefaults.standard.object(forKey: "LastKnownGoodData") as? Date
    }
    
    // MARK: - Degraded Mode Operations
    
    func getPrayerTimesInDegradedMode() -> [Prayer] {
        // Return cached data if available and recent
        if let lastUpdate = lastKnownGoodData,
           Date().timeIntervalSince(lastUpdate) < 24 * 60 * 60, // Less than 24 hours old
           !fallbackPrayerTimes.isEmpty {
            return fallbackPrayerTimes
        }
        
        // Return empty array if no fallback data
        return []
    }
    
    func getLocationInDegradedMode() -> Location? {
        return fallbackLocation
    }
    
    // MARK: - User Messaging
    
    func getDegradedModeMessage() -> String? {
        var unavailableFeatures: [String] = []
        
        // Only show network message if we've had multiple consecutive failures
        if !isNetworkAvailable && consecutiveFailures >= requiredFailuresBeforeWarning {
            unavailableFeatures.append("internet connection")
        }
        if !isLocationAvailable {
            unavailableFeatures.append("location services")
        }
        if !isNotificationAvailable {
            unavailableFeatures.append("notifications")
        }
        if !isiCloudAvailable {
            unavailableFeatures.append("iCloud sync")
        }
        
        guard !unavailableFeatures.isEmpty else { return nil }
        
        let featuresText = unavailableFeatures.joined(separator: ", ")
        return "Limited functionality: \(featuresText) unavailable. Using cached data where possible."
    }
    
    func shouldShowDegradedModeWarning() -> Bool {
        // Only show warning if network is genuinely unavailable (after multiple checks)
        let networkUnavailable = !isNetworkAvailable && consecutiveFailures >= requiredFailuresBeforeWarning
        return networkUnavailable || !isLocationAvailable
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let errorRecoveryAttempt = Notification.Name("ErrorRecoveryAttempt")
    static let showAppPreferences = Notification.Name("ShowAppPreferences")
    static let refreshAllData = Notification.Name("RefreshAllData")
    static let showLocationSearch = Notification.Name("ShowLocationSearch")
    static let resetAppData = Notification.Name("ResetAppData")
    static let networkStatusChanged = Notification.Name("NetworkStatusChanged")
}