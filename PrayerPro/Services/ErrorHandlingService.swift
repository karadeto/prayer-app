//
//  ErrorHandlingService.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Error Handling Service

@MainActor
class ErrorHandlingService: ObservableObject {
    static let shared = ErrorHandlingService()
    
    private let errorHandler = ErrorHandlerManager.shared
    private let degradationManager = GracefulDegradationManager.shared
    private let logger = ErrorLogger.shared
    
    // Published properties for UI binding
    @Published var hasActiveErrors: Bool = false
    @Published var currentError: PrayerAppError?
    @Published var isInDegradedMode: Bool = false
    @Published var degradedModeMessage: String?
    
    // Error statistics
    @Published var recentErrorCount: Int = 0
    @Published var criticalErrorCount: Int = 0
    @Published var networkErrorCount: Int = 0
    @Published var locationErrorCount: Int = 0
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupErrorMonitoring()
        updateErrorStatistics()
        updateUIProperties()
    }
    
    // MARK: - Error Monitoring
    
    private func setupErrorMonitoring() {
        // Monitor network status changes
        NotificationCenter.default.publisher(for: .networkStatusChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.degradationManager.updateFeatureAvailability()
                }
            }
            .store(in: &cancellables)
        
        // Monitor error recovery attempts
        NotificationCenter.default.publisher(for: .errorRecoveryAttempt)
            .sink { [weak self] notification in
                if let error = notification.userInfo?["error"] as? PrayerAppError,
                   let attempt = notification.userInfo?["attempt"] as? Int {
                    self?.handleRecoveryAttempt(error: error, attempt: attempt)
                }
            }
            .store(in: &cancellables)
        
        // Update statistics periodically
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateErrorStatistics()
            }
            .store(in: &cancellables)
    }
    
    private func handleRecoveryAttempt(error: PrayerAppError, attempt: Int) {
        print("🔄 Recovery attempt \(attempt) for error: \(error.localizedDescription ?? "Unknown")")
        
        // Log recovery attempt
        logger.log(error, context: ErrorContext(
            error: error,
            userAction: "automaticRecoveryAttempt",
            additionalInfo: ["attempt": attempt]
        ))
    }
    
    private func updateErrorStatistics() {
        let recentErrors = logger.getRecentErrors(limit: 50)
        let last24Hours = Date().addingTimeInterval(-24 * 60 * 60)
        
        let recent = recentErrors.filter { $0.timestamp > last24Hours }
        
        recentErrorCount = recent.count
        criticalErrorCount = recent.filter { $0.error.severity == .critical }.count
        networkErrorCount = recent.filter { $0.error.category == .network }.count
        locationErrorCount = recent.filter { $0.error.category == .location }.count
    }
    
    private func updateUIProperties() {
        hasActiveErrors = errorHandler.isShowingError
        currentError = errorHandler.currentError
        isInDegradedMode = degradationManager.shouldShowDegradedModeWarning()
        degradedModeMessage = degradationManager.getDegradedModeMessage()
    }
    
    // MARK: - Public Error Handling Methods
    
    func handleError(_ error: Error, context: String? = nil, showToUser: Bool = true) {
        errorHandler.handle(error, context: context, showToUser: showToUser)
        updateErrorStatistics()
    }
    
    func handlePrayerAppError(_ error: PrayerAppError, context: String? = nil, showToUser: Bool = true) {
        errorHandler.handle(error, context: context, showToUser: showToUser)
        updateErrorStatistics()
    }
    
    func dismissCurrentError() {
        errorHandler.dismissError()
    }
    
    func executeRecoveryAction(_ action: ErrorRecoveryAction) {
        errorHandler.executeRecoveryAction(action)
    }
    
    // MARK: - Graceful Degradation
    
    func updateSystemAvailability() {
        degradationManager.updateFeatureAvailability()
    }
    
    func storeFallbackData(prayers: [Prayer], location: Location) {
        degradationManager.storeFallbackData(prayers: prayers, location: location)
    }
    
    func getFallbackPrayerTimes() -> [Prayer] {
        return degradationManager.getPrayerTimesInDegradedMode()
    }
    
    func getFallbackLocation() -> Location? {
        return degradationManager.getLocationInDegradedMode()
    }
    
    // MARK: - Error Prevention
    
    func validateNetworkConnection() -> Bool {
        return degradationManager.isNetworkAvailable
    }
    
    func validateLocationServices() -> Bool {
        return degradationManager.isLocationAvailable
    }
    
    func validateNotificationPermissions() -> Bool {
        return degradationManager.isNotificationAvailable
    }
    
    func validateiCloudAvailability() -> Bool {
        return degradationManager.isiCloudAvailable
    }
    
    // MARK: - Error Recovery Helpers
    
    func canRetryOperation(for error: PrayerAppError) -> Bool {
        let strategy = ErrorRecoveryStrategy.strategy(for: error)
        return strategy.automaticRetry && strategy.maxRetries > 0
    }
    
    func getRecoveryStrategy(for error: PrayerAppError) -> ErrorRecoveryStrategy {
        return ErrorRecoveryStrategy.strategy(for: error)
    }
    
    // MARK: - Logging and Debugging
    
    func getErrorLog() -> [ErrorLogEntry] {
        return logger.getRecentErrors(limit: 100)
    }
    
    func exportErrorLog() -> String {
        return logger.exportLogsForDebug()
    }
    
    func clearErrorLog() {
        logger.clearLogs()
        updateErrorStatistics()
    }
    
    func logCustomError(_ message: String, severity: ErrorSeverity = .error, category: ErrorCategory = .system) {
        let error = PrayerAppError.configurationError(message)
        logger.log(error, context: ErrorContext(
            error: error,
            userAction: "customLog",
            additionalInfo: ["severity": severity, "category": category]
        ))
        updateErrorStatistics()
    }
    
    // MARK: - Health Check
    
    func performHealthCheck() -> HealthCheckResult {
        let networkHealth = degradationManager.isNetworkAvailable
        let locationHealth = degradationManager.isLocationAvailable
        let notificationHealth = degradationManager.isNotificationAvailable
        let iCloudHealth = degradationManager.isiCloudAvailable
        let cacheHealth = degradationManager.isCacheAvailable
        
        let recentCriticalErrors = logger.getErrorsBySeverity(.critical)
            .filter { $0.timestamp > Date().addingTimeInterval(-24 * 60 * 60) }
        
        let overallHealth: HealthStatus
        if !recentCriticalErrors.isEmpty {
            overallHealth = .critical
        } else if !networkHealth || !locationHealth {
            overallHealth = .degraded
        } else if recentErrorCount > 10 {
            overallHealth = .warning
        } else {
            overallHealth = .healthy
        }
        
        return HealthCheckResult(
            overallHealth: overallHealth,
            networkHealth: networkHealth,
            locationHealth: locationHealth,
            notificationHealth: notificationHealth,
            iCloudHealth: iCloudHealth,
            cacheHealth: cacheHealth,
            recentErrorCount: recentErrorCount,
            criticalErrorCount: recentCriticalErrors.count,
            lastHealthCheck: Date()
        )
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        errorHandler.cleanup()
        cancellables.removeAll()
    }
}

// MARK: - Health Check Models

enum HealthStatus {
    case healthy
    case warning
    case degraded
    case critical
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .yellow
        case .degraded: return .orange
        case .critical: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .degraded: return "minus.circle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }
    
    var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .degraded: return "Degraded"
        case .critical: return "Critical"
        }
    }
}

struct HealthCheckResult {
    let overallHealth: HealthStatus
    let networkHealth: Bool
    let locationHealth: Bool
    let notificationHealth: Bool
    let iCloudHealth: Bool
    let cacheHealth: Bool
    let recentErrorCount: Int
    let criticalErrorCount: Int
    let lastHealthCheck: Date
    
    var healthScore: Double {
        let components = [networkHealth, locationHealth, notificationHealth, iCloudHealth, cacheHealth]
        let healthyComponents = components.filter { $0 }.count
        let baseScore = Double(healthyComponents) / Double(components.count)
        
        // Reduce score based on recent errors
        let errorPenalty = min(Double(recentErrorCount) * 0.02, 0.3) // Max 30% penalty
        let criticalPenalty = min(Double(criticalErrorCount) * 0.1, 0.5) // Max 50% penalty
        
        return max(0, baseScore - errorPenalty - criticalPenalty)
    }
}

// MARK: - Error Handling Extensions

extension View {
    func handleErrors(with service: ErrorHandlingService? = nil) -> some View {
        self.withErrorHandling()
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let errorHandlingServiceUpdated = Notification.Name("ErrorHandlingServiceUpdated")
    static let healthCheckCompleted = Notification.Name("HealthCheckCompleted")
}