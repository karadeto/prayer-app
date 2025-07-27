//
//  ErrorHandlingTests.swift
//  PrayerProTests
//
//  Created by Kiro on 24.07.25.
//

import XCTest
import SwiftUI
@testable import PrayerPro

final class ErrorHandlingTests: XCTestCase {
    
    var errorHandler: ErrorHandlerManager!
    var errorLogger: ErrorLogger!
    var degradationManager: GracefulDegradationManager!
    var errorService: ErrorHandlingService!
    
    override func setUpWithError() throws {
        errorHandler = ErrorHandlerManager.shared
        errorLogger = ErrorLogger.shared
        degradationManager = GracefulDegradationManager.shared
        errorService = ErrorHandlingService.shared
        
        // Clear any existing errors
        errorLogger.clearLogs()
        errorHandler.dismissError()
    }
    
    override func tearDownWithError() throws {
        errorLogger.clearLogs()
        errorHandler.cleanup()
        errorHandler = nil
        errorLogger = nil
        degradationManager = nil
        errorService = nil
    }
    
    // MARK: - Error Classification Tests
    
    func testErrorSeverityClassification() throws {
        let networkError = PrayerAppError.networkUnavailable
        XCTAssertEqual(networkError.severity, .warning)
        
        let dataCorruption = PrayerAppError.dataCorruption
        XCTAssertEqual(dataCorruption.severity, .critical)
        
        let locationPermission = PrayerAppError.locationPermissionDenied
        XCTAssertEqual(locationPermission.severity, .warning)
        
        let serverError = PrayerAppError.apiServerError(code: 500, message: "Internal Server Error")
        XCTAssertEqual(serverError.severity, .error)
    }
    
    func testErrorCategoryClassification() throws {
        let networkError = PrayerAppError.networkUnavailable
        XCTAssertEqual(networkError.category, .network)
        
        let locationError = PrayerAppError.locationPermissionDenied
        XCTAssertEqual(locationError.category, .location)
        
        let notificationError = PrayerAppError.notificationPermissionDenied
        XCTAssertEqual(notificationError.category, .notifications)
        
        let dataError = PrayerAppError.dataCorruption
        XCTAssertEqual(dataError.category, .data)
    }
    
    // MARK: - Error Logging Tests
    
    func testErrorLogging() throws {
        let error = PrayerAppError.networkUnavailable
        let context = ErrorContext(error: error, userAction: "testAction")
        
        errorLogger.log(error, context: context)
        
        let recentErrors = errorLogger.getRecentErrors(limit: 10)
        XCTAssertEqual(recentErrors.count, 1)
        XCTAssertEqual(recentErrors.first?.error, error)
        XCTAssertEqual(recentErrors.first?.context?.userAction, "testAction")
    }
    
    func testErrorLogFiltering() throws {
        // Log different types of errors
        errorLogger.log(.networkUnavailable)
        errorLogger.log(.locationPermissionDenied)
        errorLogger.log(.dataCorruption)
        errorLogger.log(.notificationPermissionDenied)
        
        let networkErrors = errorLogger.getErrorsByCategory(.network)
        XCTAssertEqual(networkErrors.count, 1)
        
        let criticalErrors = errorLogger.getErrorsBySeverity(.critical)
        XCTAssertEqual(criticalErrors.count, 1)
        XCTAssertEqual(criticalErrors.first?.error, .dataCorruption)
    }
    
    func testErrorLogExport() throws {
        errorLogger.log(.networkUnavailable)
        errorLogger.log(.locationPermissionDenied)
        
        let exportString = errorLogger.exportLogsForDebug()
        XCTAssertTrue(exportString.contains("PrayerPro Error Log Export"))
        XCTAssertTrue(exportString.contains("Total Entries: 2"))
        XCTAssertTrue(exportString.contains("networkUnavailable"))
        XCTAssertTrue(exportString.contains("locationPermissionDenied"))
    }
    
    // MARK: - Error Recovery Strategy Tests
    
    func testNetworkErrorRecoveryStrategy() throws {
        let error = PrayerAppError.networkUnavailable
        let strategy = ErrorRecoveryStrategy.strategy(for: error)
        
        XCTAssertEqual(strategy.primaryAction, .retry)
        XCTAssertTrue(strategy.automaticRetry)
        XCTAssertEqual(strategy.maxRetries, 3)
        XCTAssertEqual(strategy.retryDelay, 5.0)
    }
    
    func testLocationPermissionRecoveryStrategy() throws {
        let error = PrayerAppError.locationPermissionDenied
        let strategy = ErrorRecoveryStrategy.strategy(for: error)
        
        XCTAssertEqual(strategy.primaryAction, .openSystemPreferences)
        XCTAssertTrue(strategy.secondaryActions.contains(.selectManualLocation))
        XCTAssertFalse(strategy.automaticRetry)
        XCTAssertEqual(strategy.maxRetries, 0)
    }
    
    func testDataCorruptionRecoveryStrategy() throws {
        let error = PrayerAppError.dataCorruption
        let strategy = ErrorRecoveryStrategy.strategy(for: error)
        
        XCTAssertEqual(strategy.primaryAction, .resetData)
        XCTAssertTrue(strategy.secondaryActions.contains(.contactSupport))
        XCTAssertFalse(strategy.automaticRetry)
    }
    
    // MARK: - Error Handler Manager Tests
    
    @MainActor
    func testErrorPresentation() throws {
        let error = PrayerAppError.networkUnavailable
        
        errorHandler.handle(error, showToUser: true)
        
        XCTAssertEqual(errorHandler.currentError, error)
        XCTAssertTrue(errorHandler.isShowingError)
        XCTAssertNotNil(errorHandler.errorRecoveryStrategy)
    }
    
    @MainActor
    func testErrorDismissal() throws {
        let error = PrayerAppError.networkUnavailable
        
        errorHandler.handle(error, showToUser: true)
        XCTAssertTrue(errorHandler.isShowingError)
        
        errorHandler.dismissError()
        XCTAssertFalse(errorHandler.isShowingError)
        XCTAssertNil(errorHandler.currentError)
    }
    
    // MARK: - Graceful Degradation Tests
    
    @MainActor
    func testFeatureAvailabilityUpdate() throws {
        degradationManager.updateFeatureAvailability()
        
        // These tests would need to be mocked in a real scenario
        // For now, we just verify the method doesn't crash
        XCTAssertNotNil(degradationManager.isNetworkAvailable)
        XCTAssertNotNil(degradationManager.isLocationAvailable)
        XCTAssertNotNil(degradationManager.isNotificationAvailable)
    }
    
    @MainActor
    func testFallbackDataStorage() throws {
        let location = try Location(
            id: UUID(),
            name: "Test Location",
            city: "Test City",
            country: "Test Country",
            latitude: 40.7128,
            longitude: -74.0060,
            diyanetId: "test123",
            isFavorite: false,
            isGPSLocation: false
        )
        
        let prayers = [
            Prayer(
                id: UUID(),
                prayerType: .fajr,
                time: Date(),
                location: location,
                isCompleted: false,
                completedAt: nil
            )
        ]
        
        degradationManager.storeFallbackData(prayers: prayers, location: location)
        
        let retrievedPrayers = degradationManager.getPrayerTimesInDegradedMode()
        let retrievedLocation = degradationManager.getLocationInDegradedMode()
        
        XCTAssertEqual(retrievedPrayers.count, 1)
        XCTAssertEqual(retrievedPrayers.first?.prayerType, .fajr)
        XCTAssertEqual(retrievedLocation?.name, "Test Location")
    }
    
    // MARK: - Error Service Integration Tests
    
    @MainActor
    func testErrorServiceHandling() throws {
        let error = URLError(.timedOut)
        
        errorService.handleError(error, context: "testOperation", showToUser: false)
        
        let recentErrors = errorService.getErrorLog()
        XCTAssertGreaterThan(recentErrors.count, 0)
        
        let lastError = recentErrors.first
        XCTAssertEqual(lastError?.error, .apiTimeout)
        XCTAssertEqual(lastError?.context?.userAction, "testOperation")
    }
    
    @MainActor
    func testHealthCheck() throws {
        let healthCheck = errorService.performHealthCheck()
        
        XCTAssertNotNil(healthCheck.overallHealth)
        XCTAssertGreaterThanOrEqual(healthCheck.healthScore, 0.0)
        XCTAssertLessThanOrEqual(healthCheck.healthScore, 1.0)
        XCTAssertNotNil(healthCheck.lastHealthCheck)
    }
    
    // MARK: - Error Mapping Tests
    
    func testURLErrorMapping() throws {
        let timeoutError = URLError(.timedOut)
        let networkError = URLError(.notConnectedToInternet)
        
        let handler = ErrorHandlerManager.shared
        
        let mappedTimeout = handler.mapToPrayerAppError(timeoutError)
        XCTAssertEqual(mappedTimeout, .apiTimeout)
        
        let mappedNetwork = handler.mapToPrayerAppError(networkError)
        XCTAssertEqual(mappedNetwork, .networkUnavailable)
    }
    
    // MARK: - Performance Tests
    
    func testErrorLoggingPerformance() throws {
        let error = PrayerAppError.networkUnavailable
        
        measure {
            for _ in 0..<100 {
                errorLogger.log(error)
            }
        }
    }
    
    func testErrorRecoveryStrategyPerformance() throws {
        let errors: [PrayerAppError] = [
            .networkUnavailable,
            .locationPermissionDenied,
            .dataCorruption,
            .apiTimeout,
            .notificationPermissionDenied
        ]
        
        measure {
            for error in errors {
                _ = ErrorRecoveryStrategy.strategy(for: error)
            }
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyErrorLog() throws {
        errorLogger.clearLogs()
        
        let recentErrors = errorLogger.getRecentErrors(limit: 10)
        XCTAssertEqual(recentErrors.count, 0)
        
        let exportString = errorLogger.exportLogsForDebug()
        XCTAssertTrue(exportString.contains("Total Entries: 0"))
    }
    
    func testMaxErrorLogEntries() throws {
        // Log more than the maximum number of entries
        for i in 0..<150 {
            errorLogger.log(.networkUnavailable, context: ErrorContext(
                error: .networkUnavailable,
                userAction: "test\(i)"
            ))
        }
        
        let recentErrors = errorLogger.getRecentErrors(limit: 200)
        XCTAssertLessThanOrEqual(recentErrors.count, 100) // Should be capped at maxLogEntries
    }
    
    @MainActor
    func testConcurrentErrorHandling() throws {
        let expectation = XCTestExpectation(description: "Concurrent error handling")
        expectation.expectedFulfillmentCount = 10
        
        for i in 0..<10 {
            DispatchQueue.global().async {
                let error = PrayerAppError.networkUnavailable
                Task { @MainActor in
                    self.errorHandler.handle(error, context: "concurrent\(i)", showToUser: false)
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        let recentErrors = errorLogger.getRecentErrors(limit: 20)
        XCTAssertGreaterThanOrEqual(recentErrors.count, 10)
    }
}