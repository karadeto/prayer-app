//
//  StatusBarView.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import SwiftData

struct StatusBarView: View {
    let currentLocation: Location?
    let nextPrayer: Prayer?
    let timeRemaining: TimeInterval
    
    @Environment(\.modelContext) private var modelContext
    @State private var todaysPrayers: [Prayer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var refreshTimer: Timer?
    @State private var timerTick: Date = Date()
    
    private let prayerTimeService = PrayerTimeService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if isLoading {
                loadingView
            } else if let errorMessage = errorMessage {
                errorView(errorMessage)
            } else {
                contentView
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 300, height: 400)
        .background(Color(NSColor.clear))
        .onAppear {
            loadTodaysPrayers()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Update timer tick every second for synchronized countdown
            let remaining = calculateDynamicTimeRemaining()
            if remaining < 3600 { // Show seconds when < 60 minutes
                timerTick = Date()
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            // Always update every minute
            timerTick = Date()
        }
        .onChange(of: currentLocation) { _, _ in
            loadTodaysPrayers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .prayerCompletionChanged)) { notification in
            // Update only the specific prayer that changed, don't reload all data
            if let changedPrayer = notification.object as? Prayer {
                updatePrayerInList(changedPrayer)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPrayerTimes)) { _ in
            // Refresh when explicitly requested
            loadTodaysPrayers()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("Prayer Times")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if let location = currentLocation {
                HStack {
                    Image(systemName: location.isGPSLocation ? "location" : "mappin")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(location.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding()
    }
    
    // MARK: - Content Views
    
    private var contentView: some View {
        VStack(spacing: 0) {
            // Next Prayer Countdown
            if let nextPrayer = nextPrayer {
                nextPrayerView(nextPrayer)
                
                Divider()
                    .padding(.horizontal)
            } else if timeRemaining > 0 {
                // During Isha - show countdown to tomorrow's Fajr
                tomorrowFajrView()
                
                Divider()
                    .padding(.horizontal)
            }
            
            // Today's Prayer Times
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(todaysPrayers) { prayer in
                        prayerRowView(prayer)
                        
                        if prayer.id != todaysPrayers.last?.id {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }
    
    private func nextPrayerView(_ prayer: Prayer) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Next Prayer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(prayer.prayerType.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(prayer.time.formattedTime)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(calculateDynamicTimeRemaining().formattedCountdown)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .monospacedDigit()
                        .id(timerTick)
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
    }
    
    private func tomorrowFajrView() -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Next Prayer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fajr")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Tomorrow")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(calculateDynamicTimeRemaining().formattedCountdown)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .monospacedDigit()
                        .id(timerTick)
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
    }
    
    private func prayerRowView(_ prayer: Prayer) -> some View {
        HStack(spacing: 12) {
            // Prayer type indicator
            Circle()
                .fill(Color.prayerColor(for: prayer.prayerType))
                .frame(width: 8, height: 8)
            
            // Prayer name
            Text(prayer.prayerType.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Prayer time
            Text(prayer.time.formattedTime)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
                .monospacedDigit()
            
            // Completion status - only show for actual prayers, not sunrise
            if prayer.prayerType != .sunrise {
                Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(prayer.isCompleted ? .green : .secondary)
                    .font(.system(size: 16))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            // Only allow toggling for actual prayers, not sunrise
            if prayer.prayerType != .sunrise {
                togglePrayerCompletion(prayer)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Loading prayer times...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                loadTodaysPrayers()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer View
    
    private var footerView: some View {
        HStack {
            Button("Show Main Window") {
                showMainWindow()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            
            Spacer()
            
            Button("Refresh") {
                loadTodaysPrayers()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding()
    }
    
    // MARK: - Data Loading
    
    private func updatePrayerInList(_ changedPrayer: Prayer) {
        // Find and update the specific prayer in our list without reloading everything
        if let index = todaysPrayers.firstIndex(where: { $0.id == changedPrayer.id }) {
            todaysPrayers[index] = changedPrayer
        }
    }
    
    private func loadTodaysPrayers() {
        guard let location = currentLocation else {
            todaysPrayers = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let prayers = try await prayerTimeService.getPrayerTimes(for: location, in: modelContext)
                let todaysOnly = prayerTimeService.getTodaysPrayers(from: prayers)
                
                await MainActor.run {
                    todaysPrayers = todaysOnly.filter { $0.prayerType != .sunrise }.sorted { $0.time < $1.time }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load prayer times"
                    isLoading = false
                }
                print("Failed to load prayers for status bar: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Timer Management
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Force view refresh every second for countdown updates
            Task { @MainActor in
                // Update a state variable to trigger view refresh
                timerTick = Date()
            }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Helper Methods
    
    private func calculateDynamicTimeRemaining() -> TimeInterval {
        // Create a temporary status to use the centralized calculation
        let status = PrayerStatus(
            currentPrayer: nil,
            nextPrayer: nextPrayer,
            timeUntilNext: timeRemaining,
            timeUntilCurrentEnds: timeRemaining,
            allPrayers: todaysPrayers
        )
        return prayerTimeService.getDynamicTimeRemaining(for: status, prayers: todaysPrayers)
    }
    
    // MARK: - Actions
    
    private func togglePrayerCompletion(_ prayer: Prayer) {
        let completionManager = PrayerCompletionManager.shared
        
        Task {
            do {
                try await completionManager.togglePrayerCompletion(prayer, in: modelContext)
                
                // The completion manager will now broadcast the change
                // and all views will refresh automatically
                
            } catch {
                print("Failed to toggle prayer completion: \(error.localizedDescription)")
            }
        }
    }
    
    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        // Find and show the main window
        for window in NSApp.windows {
            if window.identifier?.rawValue == "MainWindow" || window.contentViewController is NSHostingController<MainWindowView> {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
        
        // Close the popover
        if let popover = NSApp.windows.compactMap({ $0.contentViewController as? NSHostingController<StatusBarView> }).first?.view.window?.parent as? NSPopover {
            popover.performClose(nil)
        }
    }
}

// MARK: - Preview

#Preview {
    let location = try! Location(
        name: "Berlin",
        city: "Berlin",
        country: "Germany",
        latitude: 52.5200,
        longitude: 13.4050,
        diyanetId: "9541",
        isFavorite: true
    )
    
    let prayer = try! Prayer(
        prayerType: .dhuhr,
        time: Date().addingTimeInterval(3600), // 1 hour from now
        locationId: location.id
    )
    
    return StatusBarView(
        currentLocation: location,
        nextPrayer: prayer,
        timeRemaining: 3600
    )
    .modelContainer(for: [Location.self, Prayer.self, PrayerCompletion.self])
}
