//
//  LazyDataLoader.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import SwiftData
import OSLog
import AppKit

// MARK: - Lazy Data Loading Service

class LazyDataLoader: ObservableObject {
    static let shared = LazyDataLoader()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PrayerPro", category: "LazyDataLoader")
    private let prayerTimeService = PrayerTimeService.shared
    private let cacheManager = CacheManager.shared
    
    // Loading state tracking
    private var loadingTasks: [String: Task<Void, Never>] = [:]
    private var loadedData: Set<String> = []
    private var loadingQueue = DispatchQueue(label: "LazyDataLoader", qos: .utility)
    
    // Priority system
    private var highPriorityLocations: Set<UUID> = []
    private var mediumPriorityLocations: Set<UUID> = []
    private var lowPriorityLocations: Set<UUID> = []
    
    // Performance metrics
    private var loadStartTimes: [String: Date] = [:]
    private var loadCompletionTimes: [String: Date] = [:]
    
    var isLoading: Bool {
        return !loadingTasks.isEmpty
    }
    
    var loadingProgress: Double {
        let totalTasks = loadingTasks.count + loadedData.count
        guard totalTasks > 0 else { return 1.0 }
        return Double(loadedData.count) / Double(totalTasks)
    }
    
    private init() {
        setupPrioritySystem()
        setupBackgroundLoading()
    }
    
    // MARK: - Priority System Setup
    
    private func setupPrioritySystem() {
        // Listen for location usage patterns to adjust priorities
        NotificationCenter.default.addObserver(
            forName: .locationSelected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let location = notification.object as? Location {
                self?.updateLocationPriority(location, priority: .high)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .locationAddedToFavorites,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let location = notification.object as? Location {
                self?.updateLocationPriority(location, priority: .medium)
            }
        }
    }
    
    private func setupBackgroundLoading() {
        // Start background loading after app launch
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.startBackgroundPreloading()
        }
        
        // Listen for app becoming active to resume loading
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeBackgroundLoading()
        }
        
        // Pause loading when app becomes inactive
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pauseBackgroundLoading()
        }
    }
    
    // MARK: - Priority Management
    
    enum LoadingPriority {
        case high    // Currently selected or recently used locations
        case medium  // Favorite locations
        case low     // Other locations
    }
    
    private func updateLocationPriority(_ location: Location, priority: LoadingPriority) {
        // Remove from all priority sets first
        highPriorityLocations.remove(location.id)
        mediumPriorityLocations.remove(location.id)
        lowPriorityLocations.remove(location.id)
        
        // Add to appropriate priority set
        switch priority {
        case .high:
            highPriorityLocations.insert(location.id)
        case .medium:
            mediumPriorityLocations.insert(location.id)
        case .low:
            lowPriorityLocations.insert(location.id)
        }
        
        logger.debug("📊 Updated priority for \(location.displayName) to \(String(describing: priority))")
    }
    
    // MARK: - Lazy Loading Interface
    
    /// Load annual data for a location with specified priority
    func loadAnnualData(for location: Location, priority: LoadingPriority = .medium, in context: ModelContext) async {
        let loadingKey = "annual_\(location.id)_\(Calendar.current.component(.year, from: Date()))"
        
        // Check if already loaded or loading
        guard !loadedData.contains(loadingKey) && loadingTasks[loadingKey] == nil else {
            logger.debug("📦 Annual data for \(location.displayName) already loaded/loading")
            return
        }
        
        // Update priority
        updateLocationPriority(location, priority: priority)
        
        // Start loading task
        let task = Task { @MainActor in
            await performAnnualDataLoad(for: location, loadingKey: loadingKey, in: context)
        }
        
        loadingTasks[loadingKey] = task
        loadStartTimes[loadingKey] = Date()
        
        logger.info("🚀 Started loading annual data for \(location.displayName)")
    }
    
    /// Load daily data for a location (immediate loading)
    func loadDailyData(for location: Location, in context: ModelContext) async throws -> [Prayer] {
        let loadingKey = "daily_\(location.id)_\(Date().startOfDay)"
        
        // Check if already loaded
        if loadedData.contains(loadingKey) {
            // Try to get from cache
            if let cachedPrayers = try cacheManager.getCachedDailyPrayers(for: location.id, date: Date(), in: context) {
                logger.debug("💾 Using cached daily data for \(location.displayName)")
                return cachedPrayers
            }
        }
        
        // Load fresh data
        loadStartTimes[loadingKey] = Date()
        
        do {
            let prayers = try await prayerTimeService.fetchDailyPrayerTimes(for: location, in: context)
            
            loadedData.insert(loadingKey)
            loadCompletionTimes[loadingKey] = Date()
            
            logger.info("✅ Loaded daily data for \(location.displayName)")
            return prayers
            
        } catch {
            logger.error("❌ Failed to load daily data for \(location.displayName): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Preload data for multiple locations based on priority
    func preloadData(for locations: [Location], in context: ModelContext) {
        logger.info("🔄 Starting preload for \(locations.count) locations")
        
        // Sort locations by priority
        let sortedLocations = locations.sorted { location1, location2 in
            let priority1 = getLocationPriority(location1.id)
            let priority2 = getLocationPriority(location2.id)
            
            switch (priority1, priority2) {
            case (.high, .medium), (.high, .low), (.medium, .low):
                return true
            default:
                return false
            }
        }
        
        // Load high priority locations first
        for location in sortedLocations {
            let priority = getLocationPriority(location.id)
            
            Task {
                await loadAnnualData(for: location, priority: priority, in: context)
                
                // Add delay between loads to avoid overwhelming the system
                let delay = getLoadDelay(for: priority)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    
    // MARK: - Background Loading
    
    private func startBackgroundPreloading() {
        logger.info("🌙 Starting background preloading")
        
        Task {
            // This would typically get locations from a service with ModelContext
            // For now, we'll just log the intent
            logger.debug("Background preloading would start here with proper context")
        }
    }
    
    private func resumeBackgroundLoading() {
        logger.info("▶️ Resuming background loading")
        
        // Resume any paused loading tasks
        for (key, task) in loadingTasks {
            if task.isCancelled {
                // Restart cancelled tasks
                logger.debug("🔄 Restarting cancelled task: \(key)")
            }
        }
    }
    
    private func pauseBackgroundLoading() {
        logger.info("⏸️ Pausing background loading")
        
        // Cancel low priority tasks to save resources
        let lowPriorityTasks = loadingTasks.filter { key, _ in
            key.contains("annual") && isLowPriorityTask(key)
        }
        
        for (key, task) in lowPriorityTasks {
            task.cancel()
            loadingTasks.removeValue(forKey: key)
            logger.debug("❌ Cancelled low priority task: \(key)")
        }
    }
    
    // MARK: - Private Loading Implementation
    
    @MainActor
    private func performAnnualDataLoad(for location: Location, loadingKey: String, in context: ModelContext) async {
        do {
            // Check if data is already cached
            let currentYear = Calendar.current.component(.year, from: Date())
            if try cacheManager.hasCachedAnnualPrayers(for: location.id, year: currentYear, in: context) {
                logger.debug("💾 Annual data already cached for \(location.displayName)")
                loadedData.insert(loadingKey)
                loadingTasks.removeValue(forKey: loadingKey)
                loadCompletionTimes[loadingKey] = Date()
                return
            }
            
            // Load fresh data
            _ = try await prayerTimeService.fetchAnnualPrayerTimes(for: location, in: context)
            
            // Mark as loaded
            loadedData.insert(loadingKey)
            loadCompletionTimes[loadingKey] = Date()
            
            logger.info("✅ Completed annual data load for \(location.displayName)")
            
        } catch {
            logger.error("❌ Failed to load annual data for \(location.displayName): \(error.localizedDescription)")
        }
        
        // Clean up
        loadingTasks.removeValue(forKey: loadingKey)
    }
    
    // MARK: - Helper Methods
    
    private func getLocationPriority(_ locationId: UUID) -> LoadingPriority {
        if highPriorityLocations.contains(locationId) {
            return .high
        } else if mediumPriorityLocations.contains(locationId) {
            return .medium
        } else {
            return .low
        }
    }
    
    private func getLoadDelay(for priority: LoadingPriority) -> TimeInterval {
        switch priority {
        case .high:
            return 0.5  // 0.5 seconds between high priority loads
        case .medium:
            return 1.0  // 1 second between medium priority loads
        case .low:
            return 2.0  // 2 seconds between low priority loads
        }
    }
    
    private func isLowPriorityTask(_ taskKey: String) -> Bool {
        // Extract location ID from task key and check priority
        let components = taskKey.split(separator: "_")
        guard components.count >= 2,
              let locationIdString = components[1] as? String,
              let locationId = UUID(uuidString: String(locationIdString)) else {
            return true // Assume low priority if we can't determine
        }
        
        return getLocationPriority(locationId) == .low
    }
    
    // MARK: - Performance Metrics
    
    func getLoadingMetrics() -> LoadingMetrics {
        var totalLoadTime: TimeInterval = 0
        var completedLoads = 0
        
        for (key, startTime) in loadStartTimes {
            if let completionTime = loadCompletionTimes[key] {
                totalLoadTime += completionTime.timeIntervalSince(startTime)
                completedLoads += 1
            }
        }
        
        let averageLoadTime = completedLoads > 0 ? totalLoadTime / Double(completedLoads) : 0
        
        return LoadingMetrics(
            totalLoadsCompleted: completedLoads,
            totalLoadsInProgress: loadingTasks.count,
            averageLoadTime: averageLoadTime,
            highPriorityCount: highPriorityLocations.count,
            mediumPriorityCount: mediumPriorityLocations.count,
            lowPriorityCount: lowPriorityLocations.count
        )
    }
    
    // MARK: - Cache Management
    
    func clearLoadedDataTracking() {
        loadedData.removeAll()
        loadStartTimes.removeAll()
        loadCompletionTimes.removeAll()
        
        logger.info("🗑️ Cleared loaded data tracking")
    }
    
    func cancelAllLoading() {
        for (key, task) in loadingTasks {
            task.cancel()
            logger.debug("❌ Cancelled loading task: \(key)")
        }
        
        loadingTasks.removeAll()
        logger.info("🛑 Cancelled all loading tasks")
    }
    
    // MARK: - Cleanup
    
    deinit {
        cancelAllLoading()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Loading Metrics

struct LoadingMetrics {
    let totalLoadsCompleted: Int
    let totalLoadsInProgress: Int
    let averageLoadTime: TimeInterval
    let highPriorityCount: Int
    let mediumPriorityCount: Int
    let lowPriorityCount: Int
    
    var formattedAverageLoadTime: String {
        return String(format: "%.2f seconds", averageLoadTime)
    }
    
    var totalPriorityCount: Int {
        return highPriorityCount + mediumPriorityCount + lowPriorityCount
    }
}

// MARK: - Date Extension

extension Date {
    var startOfDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let locationAddedToFavorites = Notification.Name("LocationAddedToFavorites")
    static let lazyLoadingCompleted = Notification.Name("LazyLoadingCompleted")
    static let lazyLoadingProgressUpdated = Notification.Name("LazyLoadingProgressUpdated")
}