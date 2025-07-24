//
//  PrayerCompletionHistoryView.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import SwiftData

struct PrayerCompletionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    
    let selectedLocation: Location?
    
    @State private var selectedDate = Date()
    @State private var completionHistory: [PrayerCompletion] = []
    @State private var completionStatistics: CompletionStatistics?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var selectedDateRange: DateRange = .week
    
    private let completionManager = PrayerCompletionManager.shared
    
    enum DateRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case threeMonths = "3 Months"
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let selectedLocation = selectedLocation {
                // Header
                headerView(for: selectedLocation)
                
                // Statistics Cards
                if let stats = completionStatistics {
                    statisticsView(stats)
                }
                
                // Date Range Selector
                dateRangeSelector
                
                // History Content
                if isLoading {
                    loadingView
                } else if completionHistory.isEmpty {
                    emptyStateView
                } else {
                    historyListView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(selectedLocation != nil ? "Prayer History" : "")
        .alert("History Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: selectedLocation) { _, newLocation in
            if let location = newLocation {
                loadCompletionHistory(for: location)
            }
        }
        .onChange(of: selectedDateRange) { _, _ in
            if let location = selectedLocation {
                loadCompletionHistory(for: location)
            }
        }
        .onAppear {
            if let location = selectedLocation {
                loadCompletionHistory(for: location)
            }
        }
    }
    
    // MARK: - Header
    
    private func headerView(for location: Location) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prayer History")
                        .font(.headline)
                    Text(location.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Refresh Button
                Button(action: {
                    if let location = selectedLocation {
                        loadCompletionHistory(for: location)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Statistics View
    
    private func statisticsView(_ stats: CompletionStatistics) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120)), count: 4), spacing: 16) {
            StatCard(
                title: "Completion Rate",
                value: "\(Int(stats.completionRate))%",
                icon: "percent",
                color: .blue
            )
            
            StatCard(
                title: "Current Streak",
                value: "\(stats.currentStreak)",
                icon: "flame.fill",
                color: .orange
            )
            
            StatCard(
                title: "Longest Streak",
                value: "\(stats.longestStreak)",
                icon: "trophy.fill",
                color: .yellow
            )
            
            StatCard(
                title: "Total Prayers",
                value: "\(stats.completedPrayers)",
                icon: "checkmark.circle.fill",
                color: .green
            )
        }
        .padding()
    }
    
    // MARK: - Date Range Selector
    
    private var dateRangeSelector: some View {
        HStack {
            Text("Show:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Picker("Date Range", selection: $selectedDateRange) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .frame(width: 30, height: 30)
            
            Text("Loading prayer history...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Prayer History",
            systemImage: "calendar.badge.clock",
            description: Text("Start completing prayers to see your history here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    
    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Group completions by date
                let groupedCompletions = Dictionary(grouping: completionHistory) { completion in
                    Calendar.current.startOfDay(for: completion.date)
                }
                
                let sortedDates = groupedCompletions.keys.sorted(by: >)
                
                ForEach(sortedDates, id: \.self) { date in
                    DayCompletionView(
                        date: date,
                        completions: groupedCompletions[date] ?? [],
                        location: selectedLocation!
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func loadCompletionHistory(for location: Location) {
        Task {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
            }
            
            do {
                let endDate = Date()
                let startDate = Calendar.current.date(byAdding: .day, value: -selectedDateRange.days, to: endDate)!
                
                let history = try completionManager.getCompletionHistory(
                    from: startDate,
                    to: endDate,
                    locationId: location.id,
                    in: modelContext
                )
                
                let statistics = try completionManager.getCompletionStatistics(
                    for: location.id,
                    in: modelContext
                )
                
                await MainActor.run {
                    self.completionHistory = history
                    self.completionStatistics = statistics
                    self.isLoading = false
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
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct DayCompletionView: View {
    let date: Date
    let completions: [PrayerCompletion]
    let location: Location
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }
    
    private var completedPrayerTypes: Set<PrayerType> {
        Set(completions.map { $0.prayerType })
    }
    
    private var completionPercentage: Double {
        Double(completedPrayerTypes.count) / 5.0 * 100 // 5 prayers total
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "Today" : dateFormatter.string(from: date))
                        .font(.headline)
                        .foregroundColor(isToday ? .blue : .primary)
                    
                    Text("\(completedPrayerTypes.count) of 5 prayers completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Completion percentage
                CircularProgressView(
                    progress: completionPercentage / 100,
                    color: completionPercentage == 100 ? .green : .blue
                )
                .frame(width: 40, height: 40)
            }
            
            // Prayer completion grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 60)), count: 5), spacing: 8) {
                ForEach(PrayerType.allCases.filter { $0 != .sunrise }, id: \.self) { prayerType in
                    PrayerCompletionIndicator(
                        prayerType: prayerType,
                        isCompleted: completedPrayerTypes.contains(prayerType),
                        completionTime: completions.first { $0.prayerType == prayerType }?.completedAt
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
}

struct PrayerCompletionIndicator: View {
    let prayerType: PrayerType
    let isCompleted: Bool
    let completionTime: Date?
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: isCompleted ? "checkmark" : prayerTypeIcon)
                    .font(.caption)
                    .foregroundColor(isCompleted ? .green : .gray)
            }
            
            Text(prayerType.displayName)
                .font(.caption2)
                .foregroundColor(isCompleted ? .primary : .secondary)
            
            if isCompleted, let completionTime = completionTime {
                Text(timeFormatter.string(from: completionTime))
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
    }
    
    private var prayerTypeIcon: String {
        switch prayerType {
        case .fajr: return "sunrise"
        case .dhuhr: return "sun.max.fill"
        case .asr: return "sun.min"
        case .maghrib: return "sunset"
        case .isha: return "moon.stars"
        case .sunrise: return "sun.max"
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
            
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

#Preview {
    PrayerCompletionHistoryView(selectedLocation: nil)
        .modelContainer(for: [Location.self, Prayer.self, PrayerCompletion.self])
}