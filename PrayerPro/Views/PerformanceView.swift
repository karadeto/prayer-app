//
//  PerformanceView.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import Charts
import Network

// MARK: - Performance View

struct PerformanceView: View {
    @ObservedObject private var performanceMonitor = PerformanceMonitor.shared
    @ObservedObject private var networkOptimizer = NetworkOptimizer.shared
    @ObservedObject private var lazyDataLoader = LazyDataLoader.shared
    
    @State private var performanceReport: PerformanceReport?
    @State private var bandwidthUsage: BandwidthUsage?
    @State private var loadingMetrics: LoadingMetrics?
    @State private var showingDetailedMetrics = false
    @State private var autoRefresh = true
    
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Performance Monitor")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Monitor app performance and optimize resource usage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("Auto Refresh", isOn: $autoRefresh)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding()
                
                // Current Metrics Overview
                if let metrics = performanceMonitor.currentMetrics {
                    currentMetricsSection(metrics)
                }
                
                // Performance Charts
                if let report = performanceReport {
                    performanceChartsSection(report)
                }
                
                // Network Usage
                if let usage = bandwidthUsage {
                    networkUsageSection(usage)
                }
                
                // Loading Performance
                if let loading = loadingMetrics {
                    loadingPerformanceSection(loading)
                }
                
                // Optimization Recommendations
                optimizationRecommendationsSection()
                
                // Detailed Metrics (Expandable)
                detailedMetricsSection()
                
                // Performance Actions
                performanceActionsSection()
            }
            .padding()
        }
        .onAppear {
            refreshMetrics()
        }
        .onReceive(refreshTimer) { _ in
            if autoRefresh {
                refreshMetrics()
            }
        }
    }
    
    // MARK: - Current Metrics Section
    
    private func currentMetricsSection(_ metrics: PerformanceMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Performance")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                MetricCard(
                    title: "Memory Usage",
                    value: String(format: "%.1f MB", Double(metrics.memoryUsage) / (1024 * 1024)),
                    color: memoryUsageColor(metrics.memoryUsage),
                    icon: "memorychip"
                )
                
                MetricCard(
                    title: "CPU Usage",
                    value: String(format: "%.1f%%", metrics.cpuUsage),
                    color: cpuUsageColor(metrics.cpuUsage),
                    icon: "cpu"
                )
                
                MetricCard(
                    title: "Network Requests",
                    value: "\(metrics.networkRequests)",
                    color: .blue,
                    icon: "network"
                )
                
                MetricCard(
                    title: "Cache Hit Rate",
                    value: String(format: "%.1f%%", metrics.cacheHitRate),
                    color: cacheHitRateColor(metrics.cacheHitRate),
                    icon: "externaldrive"
                )
            }
            
            // Battery Impact Indicator
            HStack {
                Image(systemName: "battery.100")
                    .foregroundColor(metrics.batteryImpact.color)
                
                Text("Battery Impact: \(metrics.batteryImpact.rawValue)")
                    .font(.caption)
                    .foregroundColor(metrics.batteryImpact.color)
                
                Spacer()
                
                Text("Last Updated: \(metrics.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Performance Charts Section
    
    private func performanceChartsSection(_ report: PerformanceReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Trends")
                .font(.headline)
            
            // Memory Usage Chart
            VStack(alignment: .leading) {
                Text("Memory Usage Over Time")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Placeholder for actual chart
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
                    .frame(height: 100)
                    .overlay(
                        Text("Memory Usage Chart\n(Implementation needed)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    )
            }
            
            // Battery Impact Distribution
            VStack(alignment: .leading) {
                Text("Battery Impact Distribution")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    ForEach(PerformanceMetrics.BatteryImpactLevel.allCases, id: \.self) { level in
                        let count = report.batteryImpactDistribution[level] ?? 0
                        
                        VStack {
                            Text("\(count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            Rectangle()
                                .fill(level.color)
                                .frame(width: 20, height: CGFloat(count * 2))
                            
                            Text(level.rawValue)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Network Usage Section
    
    private func networkUsageSection(_ usage: BandwidthUsage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Usage")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Total Data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(usage.formattedTotalBytes)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Requests")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(usage.requestCount)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Average Speed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(usage.formattedBytesPerSecond)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            
            // Network Status
            HStack {
                Circle()
                    .fill(networkOptimizer.isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                
                Text(networkOptimizer.isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                
                if let connectionType = networkOptimizer.connectionType {
                    Text("(\(connectionType.description))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if networkOptimizer.isExpensive {
                    Text("Expensive Network")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Loading Performance Section
    
    private func loadingPerformanceSection(_ loading: LoadingMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Loading Performance")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Completed Loads")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(loading.totalLoadsCompleted)")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack(alignment: .center) {
                    Text("In Progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(loading.totalLoadsInProgress)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(loading.totalLoadsInProgress > 0 ? .orange : .primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Average Time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(loading.formattedAverageLoadTime)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            
            // Priority Distribution
            HStack {
                Text("Priority Queue:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("High: \(loading.highPriorityCount)")
                    .font(.caption)
                    .foregroundColor(.red)
                
                Text("Medium: \(loading.mediumPriorityCount)")
                    .font(.caption)
                    .foregroundColor(.orange)
                
                Text("Low: \(loading.lowPriorityCount)")
                    .font(.caption)
                    .foregroundColor(.green)
                
                Spacer()
            }
            
            // Loading Progress Bar
            if lazyDataLoader.isLoading {
                ProgressView(value: lazyDataLoader.loadingProgress)
                    .progressViewStyle(LinearProgressViewStyle())
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Optimization Recommendations Section
    
    private func optimizationRecommendationsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optimization Recommendations")
                .font(.headline)
            
            let networkRecommendations = networkOptimizer.getOptimizationRecommendations()
            let performanceRecommendations = performanceReport?.recommendations ?? []
            
            let allRecommendations = networkRecommendations + performanceRecommendations
            
            if allRecommendations.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All systems are running optimally")
                        .font(.body)
                }
            } else {
                ForEach(Array(allRecommendations.enumerated()), id: \.offset) { index, recommendation in
                    HStack(alignment: .top) {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.yellow)
                            .frame(width: 16)
                        
                        Text(recommendation)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Detailed Metrics Section
    
    private func detailedMetricsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                showingDetailedMetrics.toggle()
            }) {
                HStack {
                    Text("Detailed Metrics")
                        .font(.headline)
                    
                    Spacer()
                    
                    Image(systemName: showingDetailedMetrics ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            
            if showingDetailedMetrics {
                VStack(alignment: .leading, spacing: 8) {
                    if let report = performanceReport {
                        DetailedMetricRow(title: "Peak Memory Usage", value: report.formattedPeakMemory)
                        DetailedMetricRow(title: "Peak CPU Usage", value: report.formattedPeakCPU)
                        DetailedMetricRow(title: "Total Network Requests", value: "\(report.totalNetworkRequests)")
                        DetailedMetricRow(title: "Cache Hit Rate", value: report.formattedCacheHitRate)
                    }
                    
                    if let usage = bandwidthUsage {
                        DetailedMetricRow(title: "Session Duration", value: String(format: "%.1f minutes", usage.timeInterval / 60))
                        DetailedMetricRow(title: "Data per Request", value: usage.requestCount > 0 ? ByteCountFormatter().string(fromByteCount: Int64(usage.totalBytes / UInt64(usage.requestCount))) : "N/A")
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Performance Actions Section
    
    private func performanceActionsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Actions")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ActionButton(
                    title: "Clear Cache",
                    icon: "trash",
                    color: .orange
                ) {
                    clearCache()
                }
                
                ActionButton(
                    title: "Optimize Memory",
                    icon: "memorychip",
                    color: .blue
                ) {
                    optimizeMemory()
                }
                
                ActionButton(
                    title: "Reset Metrics",
                    icon: "arrow.clockwise",
                    color: .green
                ) {
                    resetMetrics()
                }
                
                ActionButton(
                    title: "Export Report",
                    icon: "square.and.arrow.up",
                    color: .purple
                ) {
                    exportReport()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    private func refreshMetrics() {
        performanceReport = performanceMonitor.generatePerformanceReport()
        bandwidthUsage = networkOptimizer.getBandwidthUsage()
        loadingMetrics = lazyDataLoader.getLoadingMetrics()
    }
    
    private func memoryUsageColor(_ usage: UInt64) -> Color {
        let mb = Double(usage) / (1024 * 1024)
        if mb > 100 { return .red }
        else if mb > 50 { return .orange }
        else { return .green }
    }
    
    private func cpuUsageColor(_ usage: Double) -> Color {
        if usage > 50 { return .red }
        else if usage > 25 { return .orange }
        else { return .green }
    }
    
    private func cacheHitRateColor(_ rate: Double) -> Color {
        if rate > 80 { return .green }
        else if rate > 50 { return .orange }
        else { return .red }
    }
    
    // MARK: - Actions
    
    private func clearCache() {
        Task {
            networkOptimizer.clearCache()
            // Additional cache clearing would be implemented here
        }
    }
    
    private func optimizeMemory() {
        Task {
            await performanceMonitor.performMemoryCleanup()
        }
    }
    
    private func resetMetrics() {
        networkOptimizer.resetBandwidthTracking()
        lazyDataLoader.clearLoadedDataTracking()
        refreshMetrics()
    }
    
    private func exportReport() {
        guard let report = performanceReport else { return }
        
        let reportText = """
        Performance Report - \(report.reportDate.formatted())
        
        Memory Usage:
        - Average: \(report.formattedAverageMemory)
        - Peak: \(report.formattedPeakMemory)
        
        CPU Usage:
        - Average: \(report.formattedAverageCPU)
        - Peak: \(report.formattedPeakCPU)
        
        Network:
        - Total Requests: \(report.totalNetworkRequests)
        - Cache Hit Rate: \(report.formattedCacheHitRate)
        
        Recommendations:
        \(report.recommendations.map { "- \($0)" }.joined(separator: "\n"))
        """
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(reportText, forType: .string)
    }
}

// MARK: - Supporting Views

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DetailedMetricRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extensions

extension NWInterface.InterfaceType {
    var description: String {
        switch self {
        case .wifi: return "WiFi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }
}