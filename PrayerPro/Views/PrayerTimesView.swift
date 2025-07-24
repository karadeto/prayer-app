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
    
    @State private var prayers: [Prayer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var currentPrayerStatus: PrayerStatus?
    @State private var lastStatusUpdate: Date = Date()
    @State private var shouldUpdateStatus: Bool = true
    @State private var refreshTimer: Timer?
    
    private let prayerTimeService = PrayerTimeService.shared
    private let completionManager = PrayerCompletionManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            if let selectedLocation = selectedLocation {
                // Location Header
                locationHeader(for: selectedLocation)
                
                // Prayer Times Content
                if isLoading {
                    loadingView
                } else if prayers.isEmpty {
                    emptyStateView
                } else {
                    prayerTimesList
                }
            }
        }
        .navigationTitle(selectedLocation != nil ? "Prayer Times" : "")
        .alert("Prayer Times Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: selectedLocation) { _, newLocation in
            if let location = newLocation {
                loadPrayerTimes(for: location)
            } else {
                prayers = []
                currentPrayerStatus = nil
            }
        }
        .onAppear {
            if let location = selectedLocation {
                loadPrayerTimes(for: location)
            }
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPrayerTimes)) { _ in
            if let location = selectedLocation {
                loadPrayerTimes(for: location, forceRefresh: true)
            }
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
            // Only show next prayer if it's not during Isha and next prayer exists and is today
            if let nextPrayer = status.nextPrayer, 
               status.currentPrayer?.prayerType != .isha,
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
                    
                    Text(timeRemainingText(status.timeUntilNext))
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            } else if let currentPrayer = status.currentPrayer {
                HStack {
                    Text("Current: \(currentPrayer.prayerType.displayName)")
                        .font(.title)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if status.timeUntilCurrentEnds > 0 {
                        Text("Ends in \(timeRemainingText(status.timeUntilCurrentEnds))")
                            .font(.title)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
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
                    isNextPrayer: isNextPrayer(prayer)
                ) {
                    togglePrayerCompletion(prayer)
                }
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func loadPrayerTimes(for location: Location, forceRefresh: Bool = false) {
        Task {
            await MainActor.run {
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
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        let seconds = Int(timeInterval) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if timeInterval >= 3600 { // 60 minutes or more
            return "\(minutes)m"
        } else {
            // Under 60 minutes, show seconds
            return "\(minutes)m \(seconds)s"
        }
    }
    
    // MARK: - Helper Methods
    
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                updateTimerDisplay()
            }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Prayer Time Row

struct PrayerTimeRow: View {
    let prayer: Prayer
    let isCurrentPrayer: Bool
    let isNextPrayer: Bool
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
        prayer.time < Date()
    }
    
    private var visualState: PrayerVisualState {
        completionManager.getVisualState(for: prayer)
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
            
            // Completion overlay
            if prayer.isCompleted {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.green)
                    .fontWeight(.bold)
                    .offset(x: 12, y: -12)
                    .background(
                        Circle()
                            .fill(Color.green)
                            .frame(width: 16, height: 16)
                    )
            }
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
            .frame(minWidth: 0)
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
    PrayerTimesView(selectedLocation: nil)
        .modelContainer(for: [Location.self, Prayer.self])
}
