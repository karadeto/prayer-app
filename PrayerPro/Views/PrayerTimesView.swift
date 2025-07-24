//
//  PrayerTimesView.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import SwiftData

struct PrayerTimesView: View {
    @Environment(\.modelContext) private var modelContext
    
    let selectedLocation: Location?
    
    @State private var prayers: [Prayer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var currentPrayerStatus: PrayerStatus?
    @State private var refreshTimer: Timer?
    
    private let prayerTimeService = PrayerTimeService.shared
    
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
            } else {
                // No Location Selected
                noLocationSelectedView
            }
        }
        .navigationTitle("Prayer Times")
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
            if let nextPrayer = status.nextPrayer {
                HStack {
                    Text("Next: \(nextPrayer.prayerType.displayName)")
                        .font(.title)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(timeRemainingText(status.timeUntilNext))
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            } else if let currentPrayer = status.currentPrayer {
                HStack {
                    Text("Current: \(currentPrayer.prayerType.displayName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("In Progress")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
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
    
    private var noLocationSelectedView: some View {
        ContentUnavailableView(
            "No Location Selected",
            systemImage: "location.circle",
            description: Text("Select a location from the sidebar to view prayer times")
        )
    }
    
    private var prayerTimesList: some View {
        List {
            ForEach(prayers) { prayer in
                PrayerTimeRow(
                    prayer: prayer,
                    isCurrentPrayer: currentPrayerStatus?.currentPrayer?.id == prayer.id,
                    isNextPrayer: currentPrayerStatus?.nextPrayer?.id == prayer.id
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
                    updateCurrentPrayerStatus()
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
    
    private func updateCurrentPrayerStatus() {
        guard let location = selectedLocation else { return }
        
        Task {
            let status = await prayerTimeService.getCurrentPrayerStatus(for: location, in: modelContext)
            
            await MainActor.run {
                self.currentPrayerStatus = status
            }
        }
    }
    
    private func togglePrayerCompletion(_ prayer: Prayer) {
        do {
            if prayer.isCompleted {
                prayer.markIncomplete()
            } else {
                try prayer.markCompleted()
            }
            
            // Save to context
            try modelContext.save()
            
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func timeRemainingText(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Timer Management
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            updateCurrentPrayerStatus()
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
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var isPrayerTimePassed: Bool {
        prayer.time < Date()
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
                
                Text(timeFormatter.string(from: prayer.time))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Completion Status
            if prayer.prayerType != .sunrise {
                completionButton
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(rowBackground)
        .cornerRadius(8)
    }
    
    // MARK: - Subviews
    
    private var prayerTypeIcon: some View {
        Image(systemName: prayerTypeIconName)
            .font(.title2)
            .foregroundColor(iconColor)
            .frame(width: 32, height: 32)
            .background(iconBackgroundColor)
            .cornerRadius(8)
    }
    
    private var completionButton: some View {
        Button(action: onCompletionToggle) {
            Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(prayer.isCompleted ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .help(prayer.isCompleted ? "Mark as incomplete" : "Mark as completed")
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
            return Color.orange.opacity(0.1)
        } else if isNextPrayer {
            return Color.blue.opacity(0.1)
        } else if prayer.isCompleted {
            return Color.green.opacity(0.1)
        } else {
            return Color.clear
        }
    }
}

#Preview {
    PrayerTimesView(selectedLocation: nil)
        .modelContainer(for: [Location.self, Prayer.self])
}
