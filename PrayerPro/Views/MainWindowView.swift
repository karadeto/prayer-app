//
//  MainWindowView.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import SwiftData

struct MainWindowView: View {
    @State private var selectedLocation: Location?
    @State private var viewedLocation: Location?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedTab: MainTab = .prayerTimes
    @State private var showingLocationSearch = false
    
    @EnvironmentObject private var statusBarController: StatusBarController
    
    enum MainTab: String, CaseIterable {
        case prayerTimes = "Prayer Times"
        case history = "History"
        
        var iconName: String {
            switch self {
            case .prayerTimes: return "clock"
            case .history: return "chart.line.uptrend.xyaxis"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView(
                onLocationViewed: { location in
                    // Just view the location temporarily without making it current
                    viewedLocation = location
                },
                onLocationSelected: { location in
                    // Set as the actual current location
                    selectedLocation = location
                    viewedLocation = location
                    // Update status bar widget when location changes
                    statusBarController.updateLocation(location)
                    // Post notification for other components
                    NotificationCenter.default.post(name: .locationSelected, object: location)
                },
                onShowLocationSearch: {
                    showingLocationSearch = true
                }
            )
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            if let currentLocation = viewedLocation ?? selectedLocation {
                VStack(spacing: 0) {
                    // Tab Selector
                    tabSelector
                    
                    // Content View
                    Group {
                        switch selectedTab {
                        case .prayerTimes:
                            PrayerTimesView(
                                selectedLocation: currentLocation,
                                isCurrentLocation: currentLocation.id == selectedLocation?.id
                            )
                                .id("prayer-times")
                        case .history:
                            PrayerCompletionHistoryView(selectedLocation: currentLocation)
                                .id("history")
                        }
                    }
                    .frame(minWidth: 400, minHeight: 300)
                    .animation(nil, value: selectedTab)
                }
            } else {
                // No location selected - show empty state
                noLocationSelectedView
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingLocationSearch) {
            LocationSearchView { location in
                handleNewLocationSelection(location)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            toggleSidebar()
        }
    }
    
    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .white : .primary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? Color.blue : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedTab == tab ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    private var noLocationSelectedView: some View {
        ContentUnavailableView(
            "No Location Selected",
            systemImage: "location.circle",
            description: Text("Select a location from the sidebar to view prayer times and history")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func toggleSidebar() {
        withAnimation {
            sidebarVisibility = sidebarVisibility == .all ? .detailOnly : .all
        }
    }
    
    private func handleNewLocationSelection(_ location: Location) {
        selectedLocation = location
        viewedLocation = location
        statusBarController.updateLocation(location)
        NotificationCenter.default.post(name: .locationSelected, object: location)
    }
}

#Preview {
    MainWindowView()
        .modelContainer(for: [Location.self, Prayer.self, PrayerCompletion.self])
        .frame(width: 800, height: 600)
}
