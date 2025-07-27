//
//  PerformanceMonitor.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Performance Metrics

struct PerformanceMetrics {
    let timestamp: Date
    let memoryUsage: UInt64 // in bytes
    let cpuUsage: Double // percentage
    let networkRequests: Int
    let cacheHitRate: Double // percentage
    let batteryImpact: BatteryImpactLevel
    
    enum BatteryImpactLevel: String, CaseIterable {
        case minimal = "Minimal"
        case low = "Low"
        case moderate = "Moderate"
        case high = "High"
        
        var color: Color {
            switch self {
            case .minimal: return .green
            case .low: return .yellow
            case .moderate: return .orange
            case .high: return .red
            }
        }
    }
}

// MARK: - Performance Monitor

class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PrayerPro", category: "Performance")
    private var metricsHistory: [PerformanceMetrics] = []
    private var networkRequestCount = 0
    private var cacheHits = 0
    private var cacheMisses = 0
    private var lastUpdateTime = Date()
    
    // Performance thresholds
    private let memoryWarningThreshold: UInt64 = 100 * 1024 * 1024 // 100MB
    private let cpuWarningThreshold: Double = 50.0 // 50%
    private let maxMetricsHistory = 100
    
    // Timer for periodic monitoring
    private var monitoringTimer: Timer?
    private var isMonitoring = false
    
    // Current metrics
    @Published var currentMetrics: PerformanceMetrics?
    @Published var averageMemoryUsage: UInt64 = 0
    @Published var averageCPUUsage: Double = 0.0
    @Published var totalNetworkRequests: Int = 0
    @Published var overallCacheHitRate: Double = 0.0
    
    private init() {
        startMonitoring()
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        logger.info("📊 Starting performance monitoring")
        
        // Monitor every 30 seconds to balance accuracy with resource usage
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collectMetrics()
            }
        }
        
        // Collect initial metrics
        collectMetrics()
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        logger.info("📊 Stopped performance monitoring")
    }
    
    // MARK: - Metrics Collection
    
    private func collectMetrics() {
        let memoryUsage = getMemoryUsage()
        let cpuUsage = getCPUUsage()
        let batteryImpact = calculateBatteryImpact(memory: memoryUsage, cpu: cpuUsage)
        
        let metrics = PerformanceMetrics(
            timestamp: Date(),
            memoryUsage: memoryUsage,
            cpuUsage: cpuUsage,
            networkRequests: networkRequestCount,
            cacheHitRate: calculateCacheHitRate(),
            batteryImpact: batteryImpact
        )
        
        // Update current metrics
        currentMetrics = metrics
        
        // Add to history
        metricsHistory.append(metrics)
        
        // Limit history size
        if metricsHistory.count > maxMetricsHistory {
            metricsHistory.removeFirst()
        }
        
        // Update averages
        updateAverages()
        
        // Check for performance issues
        checkPerformanceThresholds(metrics)
        
        // Log metrics periodically (every 5 minutes)
        let timeSinceLastLog = Date().timeIntervalSince(lastUpdateTime)
        if timeSinceLastLog >= 300 { // 5 minutes
            logPerformanceMetrics(metrics)
            lastUpdateTime = Date()
        }
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
    
    private func getCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            // This is a simplified CPU usage calculation
            // In a real implementation, you'd want to track CPU time over intervals
            return Double(info.resident_size) / Double(1024 * 1024) * 0.1 // Rough approximation
        } else {
            return 0.0
        }
    }
    
    private func calculateCacheHitRate() -> Double {
        let totalRequests = cacheHits + cacheMisses
        guard totalRequests > 0 else { return 0.0 }
        return Double(cacheHits) / Double(totalRequests) * 100.0
    }
    
    private func calculateBatteryImpact(memory: UInt64, cpu: Double) -> PerformanceMetrics.BatteryImpactLevel {
        let memoryMB = Double(memory) / (1024 * 1024)
        
        if cpu > 30 || memoryMB > 80 {
            return .high
        } else if cpu > 15 || memoryMB > 50 {
            return .moderate
        } else if cpu > 5 || memoryMB > 25 {
            return .low
        } else {
            return .minimal
        }
    }
    
    private func updateAverages() {
        guard !metricsHistory.isEmpty else { return }
        
        let recentMetrics = Array(metricsHistory.suffix(10)) // Last 10 measurements
        
        averageMemoryUsage = recentMetrics.reduce(0) { $0 + $1.memoryUsage } / UInt64(recentMetrics.count)
        averageCPUUsage = recentMetrics.reduce(0.0) { $0 + $1.cpuUsage } / Double(recentMetrics.count)
        totalNetworkRequests = networkRequestCount
        overallCacheHitRate = calculateCacheHitRate()
    }
    
    // MARK: - Performance Threshold Monitoring
    
    private func checkPerformanceThresholds(_ metrics: PerformanceMetrics) {
        // Memory usage warning
        if metrics.memoryUsage > memoryWarningThreshold {
            logger.warning("⚠️ High memory usage detected: \(metrics.memoryUsage / (1024 * 1024))MB")
            
            // Trigger memory cleanup
            Task {
                await performMemoryCleanup()
            }
        }
        
        // CPU usage warning
        if metrics.cpuUsage > cpuWarningThreshold {
            logger.warning("⚠️ High CPU usage detected: \(metrics.cpuUsage)%")
            
            // Reduce update frequency temporarily
            adjustUpdateFrequency(reduce: true)
        }
        
        // Low cache hit rate warning
        if metrics.cacheHitRate < 50.0 && (cacheHits + cacheMisses) > 10 {
            logger.warning("⚠️ Low cache hit rate: \(metrics.cacheHitRate)%")
        }
        
        // High battery impact warning
        if metrics.batteryImpact == .high {
            logger.warning("⚠️ High battery impact detected")
            
            // Implement battery saving measures
            enableBatterySavingMode()
        }
    }
    
    // MARK: - Performance Optimization Actions
    
    @MainActor
    func performMemoryCleanup() async {
        logger.info("🧹 Performing memory cleanup")
        
        // Clear old cache entries
        do {
            await CacheManager.shared.performMemoryCleanup()
            logger.info("✅ Cache memory cleanup completed")
        } catch {
            logger.error("❌ Cache cleanup failed: \(error.localizedDescription)")
        }
        
        // Clear old metrics history
        if metricsHistory.count > 50 {
            metricsHistory = Array(metricsHistory.suffix(50))
        }
        
        // Force garbage collection
        autoreleasepool {
            // This helps release any autoreleased objects
        }
    }
    
    private func adjustUpdateFrequency(reduce: Bool) {
        // Adjust status bar widget update frequency
        let newInterval: TimeInterval = reduce ? 60.0 : 30.0 // Reduce to 1 minute or restore to 30 seconds
        
        NotificationCenter.default.post(
            name: .adjustUpdateFrequency,
            object: nil,
            userInfo: ["interval": newInterval]
        )
        
        logger.info("🔄 Adjusted update frequency to \(newInterval) seconds")
    }
    
    private func enableBatterySavingMode() {
        logger.info("🔋 Enabling battery saving mode")
        
        // Reduce status bar widget updates
        adjustUpdateFrequency(reduce: true)
        
        // Reduce background data refresh
        NotificationCenter.default.post(
            name: .enableBatterySavingMode,
            object: nil,
            userInfo: nil
        )
        
        // Reduce monitoring frequency
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collectMetrics()
            }
        }
    }
    
    // MARK: - Metrics Tracking
    
    func recordNetworkRequest() {
        networkRequestCount += 1
    }
    
    func recordCacheHit() {
        cacheHits += 1
    }
    
    func recordCacheMiss() {
        cacheMisses += 1
    }
    
    func resetNetworkMetrics() {
        networkRequestCount = 0
        cacheHits = 0
        cacheMisses = 0
    }
    
    // MARK: - Performance Reports
    
    func generatePerformanceReport() -> PerformanceReport {
        let recentMetrics = Array(metricsHistory.suffix(20)) // Last 20 measurements
        
        return PerformanceReport(
            reportDate: Date(),
            averageMemoryUsage: averageMemoryUsage,
            peakMemoryUsage: recentMetrics.max(by: { $0.memoryUsage < $1.memoryUsage })?.memoryUsage ?? 0,
            averageCPUUsage: averageCPUUsage,
            peakCPUUsage: recentMetrics.max(by: { $0.cpuUsage < $1.cpuUsage })?.cpuUsage ?? 0.0,
            totalNetworkRequests: totalNetworkRequests,
            cacheHitRate: overallCacheHitRate,
            batteryImpactDistribution: calculateBatteryImpactDistribution(),
            recommendations: generateOptimizationRecommendations()
        )
    }
    
    private func calculateBatteryImpactDistribution() -> [PerformanceMetrics.BatteryImpactLevel: Int] {
        var distribution: [PerformanceMetrics.BatteryImpactLevel: Int] = [:]
        
        for level in PerformanceMetrics.BatteryImpactLevel.allCases {
            distribution[level] = 0
        }
        
        for metrics in metricsHistory {
            distribution[metrics.batteryImpact, default: 0] += 1
        }
        
        return distribution
    }
    
    private func generateOptimizationRecommendations() -> [String] {
        var recommendations: [String] = []
        
        if averageMemoryUsage > memoryWarningThreshold {
            recommendations.append("Consider reducing cache size or implementing more aggressive cleanup")
        }
        
        if averageCPUUsage > 20.0 {
            recommendations.append("Reduce update frequency for status bar widget")
        }
        
        if overallCacheHitRate < 70.0 {
            recommendations.append("Optimize caching strategy to improve hit rate")
        }
        
        if totalNetworkRequests > 100 {
            recommendations.append("Implement request batching to reduce network calls")
        }
        
        let highBatteryImpactCount = metricsHistory.filter { $0.batteryImpact == .high }.count
        if Double(highBatteryImpactCount) / Double(metricsHistory.count) > 0.2 {
            recommendations.append("Enable battery saving mode more aggressively")
        }
        
        if recommendations.isEmpty {
            recommendations.append("Performance is optimal - no recommendations at this time")
        }
        
        return recommendations
    }
    
    // MARK: - Logging
    
    private func logPerformanceMetrics(_ metrics: PerformanceMetrics) {
        let memoryMB = Double(metrics.memoryUsage) / (1024 * 1024)
        
        logger.info("""
        📊 Performance Metrics:
        Memory: \(String(format: "%.1f", memoryMB))MB
        CPU: \(String(format: "%.1f", metrics.cpuUsage))%
        Network Requests: \(metrics.networkRequests)
        Cache Hit Rate: \(String(format: "%.1f", metrics.cacheHitRate))%
        Battery Impact: \(metrics.batteryImpact.rawValue)
        """)
    }
    
    // MARK: - Cleanup
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - Performance Report

struct PerformanceReport {
    let reportDate: Date
    let averageMemoryUsage: UInt64
    let peakMemoryUsage: UInt64
    let averageCPUUsage: Double
    let peakCPUUsage: Double
    let totalNetworkRequests: Int
    let cacheHitRate: Double
    let batteryImpactDistribution: [PerformanceMetrics.BatteryImpactLevel: Int]
    let recommendations: [String]
    
    var formattedAverageMemory: String {
        let mb = Double(averageMemoryUsage) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
    
    var formattedPeakMemory: String {
        let mb = Double(peakMemoryUsage) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
    
    var formattedAverageCPU: String {
        return String(format: "%.1f%%", averageCPUUsage)
    }
    
    var formattedPeakCPU: String {
        return String(format: "%.1f%%", peakCPUUsage)
    }
    
    var formattedCacheHitRate: String {
        return String(format: "%.1f%%", cacheHitRate)
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let adjustUpdateFrequency = Notification.Name("AdjustUpdateFrequency")
    static let enableBatterySavingMode = Notification.Name("EnableBatterySavingMode")
    static let performanceThresholdExceeded = Notification.Name("PerformanceThresholdExceeded")
}