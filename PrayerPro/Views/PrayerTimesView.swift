//
//  PrayerTimesView.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import SwiftData
import AppKit

struct PrayerTimesView: View {
    @Environment(\.modelContext) private var modelContext
    
    let selectedLocation: Location?
    let isCurrentLocation: Bool
    
    @State private var prayers: [Prayer] = []
    @State private var isLoading = false {
        didSet {
            print("🔄 isLoading changed to: \(isLoading)")
        }
    }
    @State private var hasAttemptedLoad = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var currentPrayerStatus: PrayerStatus?
    @State private var lastStatusUpdate: Date = Date()
    @State private var shouldUpdateStatus: Bool = true
    @State private var refreshTimer: Timer?
    @State private var timerTick: Date = Date()
    @State private var isWindowFocused: Bool = true
    @State private var isLocationFavorited = false
    
    private let prayerTimeService = PrayerTimeService.shared
    private let completionManager = PrayerCompletionManager.shared
    private let favoritesManager = FavoriteLocationsManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            if let selectedLocation = selectedLocation {
                // Location Header
                locationHeader(for: selectedLocation)
                
                // Prayer Times Content
                if prayers.isEmpty && !isLoading {
                    // Check if we should load or show empty state
                    if hasAttemptedLoad {
                        emptyStateView
                            .onAppear {
                                print("📭 Empty state view appeared - isLoading: \(isLoading), prayers count: \(prayers.count)")
                            }
                    } else {
                        loadingView
                            .onAppear {
                                print("🔄 Initial loading view appeared - prayers empty, no load attempted yet")
                            }
                    }
                } else if isLoading {
                    loadingView
                        .onAppear {
                            print("🔄 Loading view appeared - isLoading: \(isLoading), prayers count: \(prayers.count)")
                        }
                } else {
                    prayerTimesList
                        .onAppear {
                            print("📋 Prayer list appeared - isLoading: \(isLoading), prayers count: \(prayers.count)")
                        }
                }
            }
        }
        .navigationTitle(selectedLocation != nil ? "Prayer Times" : "")
        .alert("Prayer Times Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: selectedLocation) { oldLocation, newLocation in
            print("🔄 selectedLocation changed from \(oldLocation?.displayName ?? "nil") to \(newLocation?.displayName ?? "nil")")
            if let location = newLocation {
                // Reset hasAttemptedLoad for new selection
                hasAttemptedLoad = false
                
                // Check if this location is favorited
                Task {
                    let isFav = await favoritesManager.isFavorite(location)
                    await MainActor.run {
                        self.isLocationFavorited = isFav
                    }
                }
                
                // Only reload if location actually changed
                if oldLocation?.id != newLocation?.id {
                    print("📍 Location changed, loading fresh data")
                    loadPrayerTimes(for: location)
                } else {
                    print("📍 Same location detected, checking cache first")
                    // Same location - try to use cached data first
                    loadPrayerTimesFromCacheFirst(for: location)
                }
            } else {
                prayers = []
                currentPrayerStatus = nil
                hasAttemptedLoad = false
                isLocationFavorited = false
            }
        }
        .onAppear {
            print("👁️ PrayerTimesView appeared for location: \(selectedLocation?.displayName ?? "nil")")
            if let location = selectedLocation {
                print("🚀 onAppear: Loading prayer times for \(location.displayName)")
                
                // Check if this location is favorited
                Task {
                    let isFav = await favoritesManager.isFavorite(location)
                    await MainActor.run {
                        self.isLocationFavorited = isFav
                    }
                }
                
                // Try to load data synchronously first
                loadPrayerTimesFromCacheFirst(for: location)
            }
            startRefreshTimer()
            
            // Listen for app activation/deactivation to optimize timer frequency
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                print("✅ App became active")
                isWindowFocused = true
                restartTimerWithOptimalInterval()
            }
            
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                print("❌ App resigned active")
                isWindowFocused = false
                restartTimerWithOptimalInterval()
            }
        }
        .onDisappear {
            stopRefreshTimer()
            NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPrayerTimes)) { _ in
            if let location = selectedLocation {
                loadPrayerTimes(for: location, forceRefresh: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .timerUpdate)) { notification in
            if let userInfo = notification.object as? [String: Any],
               let interval = userInfo["interval"] as? TimeInterval {
                print("🎯 PrayerTimesView received timer update with interval: \(interval)s")
            }
            updateTimerDisplay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .prayerCompletionChanged)) { notification in
            // Update only the specific prayer that changed, don't reload all data
            if let changedPrayer = notification.object as? Prayer {
                updatePrayerInList(changedPrayer)
            }
            // Update prayer status for visual feedback
            updateCurrentPrayerStatus(force: false)
        }
    }
    
    // MARK: - Location Header
    
    private func locationHeader(for location: Location) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: location.isGPSLocation ? "location.fill" : "mappin.circle.fill")
                    .foregroundColor(location.isGPSLocation ? .blue : .green)
                
                VStack(alignment: .leading, spacing: 2) {
                    if location.isGPSLocation {
                        Text("Current Location")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(location.displayName)
                            .font(.headline)
                            .padding(.horizontal, 2)
                            .lineLimit(1)
                    } else {
                        Text(location.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(location.country)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Action buttons for different location types
                HStack(spacing: 8) {
                    // Add to Favorites Button (for GPS locations that aren't favorited)
                    if location.isGPSLocation && !isLocationFavorited {
                        Button(action: {
                            Task {
                                do {
                                    try await favoritesManager.addToFavorites(location)
                                    await MainActor.run {
                                        isLocationFavorited = true
                                    }
                                } catch {
                                    // Handle error silently or show alert
                                    print("Failed to add GPS location to favorites: \(error.localizedDescription)")
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.caption)
                                Text("Add to Favorites")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Save this GPS location to your favorites")
                    }
                    
                    // Set as Current Location Button (for non-current locations)
                    if !isCurrentLocation {
                        Button(action: {
                            // Send notification to set this location as current
                            NotificationCenter.default.post(name: .locationSelected, object: location)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("Set as Current Location")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Set this location as your current location")
                    }
                }
                
                // Refresh Button
                Button(action: {
                    if let location = selectedLocation {
                        loadPrayerTimes(for: location, forceRefresh: true)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            
            // Date Header
            dateHeaderView
            
            // Current Prayer Status
            if let status = currentPrayerStatus {
                currentPrayerStatusView(status)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Date Header
    
    private var dateHeaderView: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(.secondary)
            
            Text(formatTodaysDate())
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    private func formatTodaysDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }
    
    // MARK: - Current Prayer Status
    
    private func currentPrayerStatusView(_ status: PrayerStatus) -> some View {
        VStack(spacing: 4) {
            // Show next prayer countdown - either today's next prayer or tomorrow's Fajr during Isha
            if let nextPrayer = status.nextPrayer, 
               Calendar.current.isDateInToday(nextPrayer.time) {
                HStack {
                    Text("Next: \(nextPrayer.prayerType.displayName)")
                        .font(.title)
                        .fontWeight(.medium)
                    
                    Spacer()

                    Text("in")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text(timeRemainingText(prayerTimeService.getDynamicTimeRemaining(for: status, prayers: prayers)))
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .id(timerTick)
                }
            } else if status.timeUntilNext > 0 {
                // During Isha - show countdown to tomorrow's Fajr
                HStack {
                    Text("Next: Fajr (Tomorrow)")
                        .font(.title)
                        .fontWeight(.medium)
                    
                    Spacer()

                    Text("in")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text(timeRemainingText(prayerTimeService.getDynamicTimeRemaining(for: status, prayers: prayers)))
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .id(timerTick)
                }
            } else if let currentPrayer = status.currentPrayer {
                HStack {
                    Text("Current: \(currentPrayer.prayerType.displayName)")
                        .font(.title)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if status.timeUntilCurrentEnds > 0 {
                        Text("Ends in \(timeRemainingText(calculateTimeRemaining(for: getNextPrayerAfter(status.currentPrayer))))")
                            .font(.title)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                            .id(timerTick)
                    } else {
                        Text("In Progress")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .frame(width: 30, height: 30)
            
            Text("Loading prayer times...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Prayer Times Available",
            systemImage: "moon.stars",
            description: Text("Unable to load prayer times for this location. Please try again.")
        )
    }
    
    
    private var prayerTimesList: some View {
        List {
            ForEach(prayers) { prayer in
                PrayerTimeRow(
                    prayer: prayer,
                    isCurrentPrayer: isCurrentPrayer(prayer),
                    isNextPrayer: isNextPrayer(prayer),
                    nextPrayer: currentPrayerStatus?.nextPrayer,
                    allPrayers: prayers
                ) {
                    togglePrayerCompletion(prayer)
                }
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func updatePrayerInList(_ changedPrayer: Prayer) {
        // Find and update the specific prayer in our list without reloading everything
        if let index = prayers.firstIndex(where: { $0.id == changedPrayer.id }) {
            prayers[index] = changedPrayer
        }
    }
    
    private func loadPrayerTimesFromCacheFirst(for location: Location) {
        print("🔍 Checking cache for \(location.displayName)")
        
        // Mark that we've attempted to load
        self.hasAttemptedLoad = true
        
        // First check if PrayerTimeService has valid in-memory cache for this location
        if let cachedPrayers = prayerTimeService.getCachedPrayersIfValid(for: location) {
            let todaysPrayers = prayerTimeService.getTodaysPrayers(from: cachedPrayers)
            
            if !todaysPrayers.isEmpty {
                self.prayers = todaysPrayers.sorted { $0.time < $1.time }
                self.isLoading = false
                
                // Calculate status locally without async calls
                let sortedPrayers = todaysPrayers.sorted { $0.time < $1.time }
                let (currentPrayer, nextPrayer) = prayerTimeService.getCurrentPrayerPeriod(from: sortedPrayers)
                
                var timeUntilNext: TimeInterval = 0
                if let nextPrayer = nextPrayer {
                    timeUntilNext = max(0, nextPrayer.time.timeIntervalSince(Date()))
                }
                
                self.currentPrayerStatus = PrayerStatus(
                    currentPrayer: currentPrayer,
                    nextPrayer: nextPrayer,
                    timeUntilNext: timeUntilNext,
                    timeUntilCurrentEnds: timeUntilNext,
                    allPrayers: sortedPrayers
                )
                self.lastStatusUpdate = Date()
                
                print("✅ Used in-memory cache for \(location.displayName)")
                return
            }
        }
        
        // Fallback: Try SwiftData cache
        do {
            let cacheManager = CacheManager.shared
            if try cacheManager.hasCachedDailyPrayers(for: location.id, date: Date(), in: modelContext),
               let cachedPrayers = try cacheManager.getCachedDailyPrayers(for: location.id, date: Date(), in: modelContext),
               !cachedPrayers.isEmpty {
                
                let todaysPrayers = prayerTimeService.getTodaysPrayers(from: cachedPrayers)
                self.prayers = todaysPrayers.sorted { $0.time < $1.time }
                self.isLoading = false
                
                print("✅ Used SwiftData cache for \(location.displayName)")
                
                // Update status in background to avoid blocking
                Task {
                    await updateCurrentPrayerStatus(force: true)
                }
                return
            }
        } catch {
            print("❌ Cache check failed: \(error.localizedDescription)")
        }
        
        // Last resort: full load
        print("⚠️ No cache found, loading fresh data for \(location.displayName)")
        loadPrayerTimes(for: location)
    }
    
    private func loadPrayerTimes(for location: Location, forceRefresh: Bool = false) {
        Task {
            await MainActor.run {
                hasAttemptedLoad = true
                isLoading = true
                errorMessage = nil
            }
            
            do {
                let fetchedPrayers = try await prayerTimeService.getPrayerTimes(for: location, in: modelContext)
                let todaysPrayers = prayerTimeService.getTodaysPrayers(from: fetchedPrayers)
                
                await MainActor.run {
                    self.prayers = todaysPrayers.sorted { $0.time < $1.time }
                    self.isLoading = false
                    
                    // Update current prayer status
                    updateCurrentPrayerStatus(force: true)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func updateCurrentPrayerStatus(force: Bool = false) {
        guard let location = selectedLocation else { return }
        
        // Only update prayer status every 30 seconds unless forced
        let now = Date()
        if !force && now.timeIntervalSince(lastStatusUpdate) < 30 {
            return
        }
        
        Task {
            let status = await prayerTimeService.getCurrentPrayerStatus(for: location, in: modelContext)
            
            await MainActor.run {
                self.currentPrayerStatus = status
                self.lastStatusUpdate = now
            }
        }
    }
    
    private func updateTimerDisplay() {
        // Update timer tick to trigger view refresh
        timerTick = Date()
        print("⏰ Timer tick updated (focused: \(isWindowFocused))")
        
        // Check if we need to adjust timer frequency
        let currentInterval = refreshTimer?.timeInterval ?? 1.0
        let optimalInterval = getOptimalUpdateInterval()
        if abs(optimalInterval - currentInterval) > 0.1 {
            restartTimerWithInterval(optimalInterval)
        }
        
        // Force status update every 30 seconds or if we don't have status yet
        if currentPrayerStatus == nil || Date().timeIntervalSince(lastStatusUpdate) >= 30 {
            updateCurrentPrayerStatus(force: true)
        } else {
            // Just trigger a view refresh for countdown update
            shouldUpdateStatus.toggle()
        }
    }
    
    private func togglePrayerCompletion(_ prayer: Prayer) {
        Task {
            do {
                try await completionManager.togglePrayerCompletion(prayer, in: modelContext)
                
                // Force save and refresh to ensure persistence
                await MainActor.run {
                    try? modelContext.save()
                    // Trigger view refresh
                    updateCurrentPrayerStatus(force: true)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func timeRemainingText(_ timeInterval: TimeInterval) -> String {
        // Calculate remaining time dynamically based on current time
        let remaining = max(0, timeInterval)
        let hours = Int(remaining) / 3600
        let minutes = Int(remaining) % 3600 / 60
        let seconds = Int(remaining) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if remaining >= 60 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateTimeRemaining(for prayer: Prayer?) -> TimeInterval {
        guard let prayer = prayer else { return 0 }
        return max(0, prayer.time.timeIntervalSince(Date()))
    }
    
    
    
    private func getNextPrayerAfter(_ currentPrayer: Prayer?) -> Prayer? {
        guard let current = currentPrayer else { return nil }
        
        // Find the next prayer in today's list
        let sortedPrayers = prayers.sorted { $0.time < $1.time }
        if let currentIndex = sortedPrayers.firstIndex(where: { $0.prayerType == current.prayerType }),
           currentIndex + 1 < sortedPrayers.count {
            return sortedPrayers[currentIndex + 1]
        }
        
        return nil
    }
    
    private func isCurrentPrayer(_ prayer: Prayer) -> Bool {
        guard let currentPrayer = currentPrayerStatus?.currentPrayer else { return false }
        
        // Match by prayer type and time since IDs might be different for estimated prayers
        return currentPrayer.prayerType == prayer.prayerType &&
               Calendar.current.isDate(currentPrayer.time, inSameDayAs: prayer.time) &&
               abs(currentPrayer.time.timeIntervalSince(prayer.time)) < 300 // Within 5 minutes
    }
    
    private func isNextPrayer(_ prayer: Prayer) -> Bool {
        guard let nextPrayer = currentPrayerStatus?.nextPrayer else { return false }
        
        // Only mark as next if it's today's prayer (not tomorrow's Fajr)
        let isToday = Calendar.current.isDateInToday(prayer.time)
        if !isToday { return false }
        
        // Match by prayer type and time
        return nextPrayer.prayerType == prayer.prayerType &&
               Calendar.current.isDate(nextPrayer.time, inSameDayAs: prayer.time) &&
               abs(nextPrayer.time.timeIntervalSince(prayer.time)) < 300 // Within 5 minutes
    }
    
    
    // MARK: - Timer Management
    
    private func startRefreshTimer() {
        restartTimerWithOptimalInterval()
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func getTimerInterval() -> TimeInterval {
        guard let status = currentPrayerStatus else { 
            print("🔍 getTimerInterval: No status, returning 1.0")
            return 1.0 
        }
        
        // Get the shortest time remaining that we need to display using centralized calculation
        let timeToNext = prayerTimeService.getDynamicTimeRemaining(for: status, prayers: prayers)
        let timeToCurrent = status.currentPrayer != nil ? calculateTimeRemaining(for: getNextPrayerAfter(status.currentPrayer)) : 0
        
        let shortestTime = min(timeToNext > 0 ? timeToNext : Double.infinity, 
                              timeToCurrent > 0 ? timeToCurrent : Double.infinity)
        
        print("🔍 getTimerInterval: focused=\(isWindowFocused), timeToNext=\(timeToNext), shortestTime=\(shortestTime)")
        
        // Optimize based on window focus and time remaining
        if !isWindowFocused {
            // When window is not focused, update less frequently to save resources
            print("🔍 getTimerInterval: Not focused, returning 60.0")
            return 60.0 // Update every minute when not focused
        } else if shortestTime < 3600 { // Less than 60 minutes and focused
            print("🔍 getTimerInterval: Focused and < 1 hour, returning 1.0")
            return 1.0 // Update every second to show seconds
        } else {
            print("🔍 getTimerInterval: Focused but > 1 hour, returning 60.0")
            return 60.0 // Update every minute when only showing hours/minutes
        }
    }
    
    private func getOptimalUpdateInterval() -> TimeInterval {
        return getTimerInterval()
    }
    
    private func restartTimerWithInterval(_ interval: TimeInterval) {
        print("🔄 Invalidating old timer and creating new one with interval: \(interval)s")
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                print("📍 Timer fired with interval: \(interval)s at \(Date())")
                // Since this is a struct, we need to trigger the timer through a different mechanism
                // Let's use a notification instead
                NotificationCenter.default.post(name: .timerUpdate, object: ["interval": interval])
            }
        }
        print("✅ New timer created with interval: \(interval)s")
    }
    
    private func restartTimerWithOptimalInterval() {
        let optimalInterval = getOptimalUpdateInterval()
        print("🔄 Restarting timer with optimal interval: \(optimalInterval)s (focused: \(isWindowFocused))")
        restartTimerWithInterval(optimalInterval)
    }
}

// MARK: - Prayer Time Row

struct PrayerTimeRow: View {
    let prayer: Prayer
    let isCurrentPrayer: Bool
    let isNextPrayer: Bool
    let nextPrayer: Prayer?
    let allPrayers: [Prayer]
    let onCompletionToggle: () -> Void
    
    @State private var isHovered = false
    @State private var showCompletionAnimation = false
    
    private let completionManager = PrayerCompletionManager.shared
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var isPrayerTimePassed: Bool {
        // Use the same visual state logic to determine if prayer is missed
        visualState == .missed
    }
    
    private var visualState: PrayerVisualState {
        completionManager.getVisualState(for: prayer, nextPrayer: nextPrayer, allPrayers: allPrayers)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Prayer Type Icon
            prayerTypeIcon
            
            // Prayer Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(prayer.prayerType.displayName)
                        .font(.headline)
                        .foregroundColor(textColor)
                        .strikethrough(prayer.isCompleted, color: .secondary)
                    
                    // Status badges
                    statusBadges
                    
                    // Completion timestamp
                    if prayer.isCompleted, let completedAt = prayer.completedAt {
                        Text("✓ \(formatCompletionTime(completedAt))")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(3)
                    }
                }
                
                HStack {
                    Text(timeFormatter.string(from: prayer.time))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Time status indicator
                    if isPrayerTimePassed && !prayer.isCompleted {
                        Text("• Missed")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Completion Status
            if prayer.prayerType != .sunrise {
                completionButton
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(rowBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .scaleEffect(showCompletionAnimation ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showCompletionAnimation)
        .onHover { hovering in
            isHovered = hovering
        }
        .onReceive(NotificationCenter.default.publisher(for: .prayerCompletionChanged)) { notification in
            if let notificationPrayer = notification.object as? Prayer,
               notificationPrayer.id == prayer.id {
                withAnimation {
                    showCompletionAnimation = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showCompletionAnimation = false
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var prayerTypeIcon: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 40, height: 40)
            
            Image(systemName: prayerTypeIconName)
                .font(.title2)
                .foregroundColor(iconColor)
            
        }
    }
    
    private var statusBadges: some View {
        HStack(spacing: 4) {
            if isCurrentPrayer {
                Text("NOW")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .cornerRadius(4)
            } else if isNextPrayer {
                Text("NEXT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
            }
        }
    }
    
    private var completionButton: some View {
        Button(action: {
            onCompletionToggle()
        }) {
            HStack(spacing: 6) {
                Image(systemName: visualState.iconName)
                    .font(.title2)
                    .foregroundColor(Color(visualState.color))
                
                if isHovered {
                    Text(prayer.isCompleted ? "Undo" : "Done")
                        .font(.caption)
                        .foregroundColor(Color(visualState.color))
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(minWidth: 40)
            .padding(.horizontal, isHovered ? 8 : 4)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(visualState.color).opacity(isHovered ? 0.1 : 0))
            )
        }
        .buttonStyle(.plain)
        .help(prayer.isCompleted ? "Mark as incomplete" : "Mark as completed")
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
    
    // MARK: - Computed Properties
    
    private var prayerTypeIconName: String {
        switch prayer.prayerType {
        case .fajr:
            return "sunrise"
        case .sunrise:
            return "sun.max"
        case .dhuhr:
            return "sun.max.fill"
        case .asr:
            return "sun.min"
        case .maghrib:
            return "sunset"
        case .isha:
            return "moon.stars"
        }
    }
    
    private var iconColor: Color {
        switch prayer.prayerType {
        case .fajr:
            return .purple
        case .sunrise:
            return .orange
        case .dhuhr:
            return .yellow
        case .asr:
            return .orange
        case .maghrib:
            return .red
        case .isha:
            return .indigo
        }
    }
    
    private var iconBackgroundColor: Color {
        iconColor.opacity(0.2)
    }
    
    private var textColor: Color {
        if isCurrentPrayer {
            return .primary
        } else if isPrayerTimePassed {
            return .secondary
        } else {
            return .primary
        }
    }
    
    private var rowBackground: Color {
        if isCurrentPrayer {
            return Color.orange.opacity(0.15)
        } else if isNextPrayer {
            return Color.blue.opacity(0.15)
        } else if prayer.isCompleted {
            return Color.green.opacity(0.1)
        } else if isPrayerTimePassed {
            return Color.orange.opacity(0.05)
        } else {
            return Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.8 : 0.3)
        }
    }
    
    private var borderColor: Color {
        if prayer.isCompleted {
            return Color.green.opacity(0.3)
        } else if isCurrentPrayer {
            return Color.orange.opacity(0.5)
        } else if isNextPrayer {
            return Color.blue.opacity(0.5)
        } else {
            return Color.clear
        }
    }
    
    private var borderWidth: CGFloat {
        if prayer.isCompleted || isCurrentPrayer || isNextPrayer {
            return 1.5
        } else {
            return 0
        }
    }
    
    private func formatCompletionTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    PrayerTimesView(selectedLocation: nil, isCurrentLocation: false)
        .modelContainer(for: [Location.self, Prayer.self])
}
