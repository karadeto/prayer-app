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
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedTab: MainTab = .prayerTimes
    
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
            SidebarView { location in
                selectedLocation = location
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            if selectedLocation != nil {
                VStack(spacing: 0) {
                    // Tab Selector
                    tabSelector
                    
                    // Content View
                    Group {
                        switch selectedTab {
                        case .prayerTimes:
                            PrayerTimesView(selectedLocation: selectedLocation)
                                .id("prayer-times")
                        case .history:
                            PrayerCompletionHistoryView(selectedLocation: selectedLocation)
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            toggleSidebar()
        }
    }
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.blue : Color.clear)
                    )
                }
                .buttonStyle(.plain)
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
}

#Preview {
    MainWindowView()
        .modelContainer(for: [Location.self, Prayer.self, PrayerCompletion.self])
        .frame(width: 800, height: 600)
}