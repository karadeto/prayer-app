//
//  NetworkOptimizer.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import Foundation
import Network
import OSLog

// MARK: - Network Optimization Service

class NetworkOptimizer: ObservableObject {
    static let shared = NetworkOptimizer()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PrayerPro", category: "NetworkOptimizer")
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkOptimizer", qos: .utility)
    
    // Network state
    var isConnected = false
    var connectionType: NWInterface.InterfaceType?
    var isExpensive = false
    var isConstrained = false
    
    // Request batching
    private var pendingRequests: [NetworkRequest] = []
    private var batchTimer: Timer?
    private let batchInterval: TimeInterval = 2.0 // Batch requests every 2 seconds
    private let maxBatchSize = 5
    
    // Request deduplication
    private var activeRequests: Set<String> = []
    private var requestCache: [String: (Date, Any)] = [:]
    private let cacheTimeout: TimeInterval = 30.0 // Cache responses for 30 seconds
    
    // Bandwidth monitoring
    private var bytesTransferred: UInt64 = 0
    private var requestCount = 0
    private var lastResetTime = Date()
    
    private init() {
        startNetworkMonitoring()
        setupBatchTimer()
    }
    
    // MARK: - Network Monitoring
    
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkState(path)
            }
        }
        monitor.start(queue: queue)
    }
    
    private func updateNetworkState(_ path: NWPath) {
        isConnected = path.status == .satisfied
        connectionType = path.availableInterfaces.first?.type
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        
        logger.info("📡 Network state updated: connected=\(self.isConnected), type=\(String(describing: self.connectionType)), expensive=\(self.isExpensive), constrained=\(self.isConstrained)")
        
        // Adjust optimization strategy based on network conditions
        adjustOptimizationStrategy()
        
        // Notify performance monitor
        PerformanceMonitor.shared.recordNetworkRequest()
    }
    
    private func adjustOptimizationStrategy() {
        if isExpensive || isConstrained {
            // Enable aggressive optimization for expensive/constrained networks
            enableAggressiveOptimization()
        } else if connectionType == .wifi {
            // Use normal optimization for WiFi
            enableNormalOptimization()
        } else {
            // Use conservative optimization for cellular
            enableConservativeOptimization()
        }
    }
    
    // MARK: - Optimization Strategies
    
    private func enableAggressiveOptimization() {
        logger.info("🔥 Enabling aggressive network optimization")
        
        // Increase batch interval to reduce requests
        setupBatchTimer(interval: 5.0)
        
        // Clear old cache entries more aggressively
        cleanupCache(maxAge: 15.0)
        
        // Notify other services to reduce network usage
        NotificationCenter.default.post(
            name: .networkOptimizationModeChanged,
            object: nil,
            userInfo: ["mode": "aggressive"]
        )
    }
    
    private func enableNormalOptimization() {
        logger.info("📡 Enabling normal network optimization")
        
        // Use standard batch interval
        setupBatchTimer(interval: 2.0)
        
        // Standard cache cleanup
        cleanupCache(maxAge: 30.0)
        
        NotificationCenter.default.post(
            name: .networkOptimizationModeChanged,
            object: nil,
            userInfo: ["mode": "normal"]
        )
    }
    
    private func enableConservativeOptimization() {
        logger.info("📱 Enabling conservative network optimization")
        
        // Slightly longer batch interval for cellular
        setupBatchTimer(interval: 3.0)
        
        // Keep cache longer on cellular
        cleanupCache(maxAge: 60.0)
        
        NotificationCenter.default.post(
            name: .networkOptimizationModeChanged,
            object: nil,
            userInfo: ["mode": "conservative"]
        )
    }
    
    // MARK: - Request Batching
    
    private func setupBatchTimer(interval: TimeInterval = 2.0) {
        batchTimer?.invalidate()
        batchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.processBatchedRequests()
        }
    }
    
    func addToBatch(_ request: NetworkRequest) {
        // Check for duplicate requests
        let requestKey = request.cacheKey
        if activeRequests.contains(requestKey) {
            logger.debug("🔄 Skipping duplicate request: \(requestKey)")
            return
        }
        
        // Check cache first
        if let (cacheTime, cachedResponse) = requestCache[requestKey],
           Date().timeIntervalSince(cacheTime) < cacheTimeout {
            logger.debug("💾 Using cached response for: \(requestKey)")
            request.completion(.success(cachedResponse))
            return
        }
        
        // Add to batch
        pendingRequests.append(request)
        activeRequests.insert(requestKey)
        
        // Process immediately if batch is full
        if pendingRequests.count >= maxBatchSize {
            processBatchedRequests()
        }
    }
    
    private func processBatchedRequests() {
        guard !pendingRequests.isEmpty else { return }
        
        let batch = Array(pendingRequests.prefix(maxBatchSize))
        pendingRequests.removeFirst(min(maxBatchSize, pendingRequests.count))
        
        logger.info("📦 Processing batch of \(batch.count) requests")
        
        // Group requests by endpoint for potential optimization
        let groupedRequests = Dictionary(grouping: batch) { $0.endpoint }
        
        for (endpoint, requests) in groupedRequests {
            processBatchForEndpoint(endpoint, requests: requests)
        }
    }
    
    private func processBatchForEndpoint(_ endpoint: String, requests: [NetworkRequest]) {
        // For now, process requests individually
        // In a real implementation, you might combine multiple requests into a single API call
        for request in requests {
            processIndividualRequest(request)
        }
    }
    
    private func processIndividualRequest(_ request: NetworkRequest) {
        Task {
            do {
                let response = try await performNetworkRequest(request)
                
                // Cache the response
                requestCache[request.cacheKey] = (Date(), response)
                
                // Update bandwidth tracking
                bytesTransferred += UInt64(request.estimatedSize)
                requestCount += 1
                
                // Complete the request
                request.completion(.success(response))
                
                // Remove from active requests
                activeRequests.remove(request.cacheKey)
                
            } catch {
                logger.error("❌ Request failed: \(error.localizedDescription)")
                request.completion(.failure(error))
                activeRequests.remove(request.cacheKey)
            }
        }
    }
    
    private func performNetworkRequest(_ request: NetworkRequest) async throws -> Any {
        // This would integrate with your existing DiyanetAPIClient
        // For now, we'll simulate the request
        
        switch request.type {
        case .dailyPrayerTimes:
            // Simulate daily prayer times request
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return "Daily prayer times response"
            
        case .annualPrayerTimes:
            // Simulate annual prayer times request
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            return "Annual prayer times response"
            
        case .locationSearch:
            // Simulate location search request
            try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
            return "Location search response"
            
        case .reverseGeocode:
            // Simulate reverse geocode request
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return "Reverse geocode response"
        }
    }
    
    // MARK: - Cache Management
    
    private func cleanupCache(maxAge: TimeInterval) {
        let cutoffTime = Date().addingTimeInterval(-maxAge)
        
        let keysToRemove = requestCache.compactMap { (key, value) in
            let (cacheTime, _) = value
            return cacheTime < cutoffTime ? key : nil
        }
        
        for key in keysToRemove {
            requestCache.removeValue(forKey: key)
        }
        
        if !keysToRemove.isEmpty {
            logger.debug("🧹 Cleaned up \(keysToRemove.count) cached responses")
        }
    }
    
    func clearCache() {
        requestCache.removeAll()
        activeRequests.removeAll()
        logger.info("🗑️ Network cache cleared")
    }
    
    // MARK: - Bandwidth Monitoring
    
    func getBandwidthUsage() -> BandwidthUsage {
        let timeInterval = Date().timeIntervalSince(lastResetTime)
        let bytesPerSecond = timeInterval > 0 ? Double(bytesTransferred) / timeInterval : 0
        
        return BandwidthUsage(
            totalBytes: bytesTransferred,
            requestCount: requestCount,
            averageBytesPerSecond: bytesPerSecond,
            timeInterval: timeInterval
        )
    }
    
    func resetBandwidthTracking() {
        bytesTransferred = 0
        requestCount = 0
        lastResetTime = Date()
    }
    
    // MARK: - Optimization Recommendations
    
    func getOptimizationRecommendations() -> [String] {
        var recommendations: [String] = []
        
        let usage = getBandwidthUsage()
        
        if usage.averageBytesPerSecond > 10_000 { // 10KB/s
            recommendations.append("High bandwidth usage detected. Consider reducing update frequency.")
        }
        
        if requestCount > 100 {
            recommendations.append("High request count. Consider implementing more aggressive caching.")
        }
        
        if isExpensive {
            recommendations.append("Expensive network detected. Enable data saving mode.")
        }
        
        if isConstrained {
            recommendations.append("Constrained network detected. Reduce background updates.")
        }
        
        let cacheHitRate = Double(requestCache.count) / Double(max(requestCount, 1))
        if cacheHitRate < 0.3 {
            recommendations.append("Low cache hit rate. Consider longer cache durations.")
        }
        
        if recommendations.isEmpty {
            recommendations.append("Network usage is optimized.")
        }
        
        return recommendations
    }
    
    // MARK: - Public Interface
    
    func shouldDeferRequest() -> Bool {
        return isExpensive || isConstrained || !isConnected
    }
    
    func getOptimalRequestDelay() -> TimeInterval {
        if isExpensive {
            return 5.0 // 5 second delay for expensive networks
        } else if isConstrained {
            return 3.0 // 3 second delay for constrained networks
        } else {
            return 0.0 // No delay for normal networks
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        monitor.cancel()
        batchTimer?.invalidate()
    }
}

// MARK: - Network Request Model

struct NetworkRequest {
    let id = UUID()
    let type: RequestType
    let endpoint: String
    let parameters: [String: Any]
    let estimatedSize: Int
    let completion: (Result<Any, Error>) -> Void
    
    enum RequestType {
        case dailyPrayerTimes
        case annualPrayerTimes
        case locationSearch
        case reverseGeocode
    }
    
    var cacheKey: String {
        let paramString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return "\(endpoint)?\(paramString)"
    }
}

// MARK: - Bandwidth Usage Model

struct BandwidthUsage {
    let totalBytes: UInt64
    let requestCount: Int
    let averageBytesPerSecond: Double
    let timeInterval: TimeInterval
    
    var formattedTotalBytes: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalBytes))
    }
    
    var formattedBytesPerSecond: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(averageBytesPerSecond)))/s"
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let networkOptimizationModeChanged = Notification.Name("NetworkOptimizationModeChanged")
    static let bandwidthUsageUpdated = Notification.Name("BandwidthUsageUpdated")
}
