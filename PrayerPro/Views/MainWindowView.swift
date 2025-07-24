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
    
    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView { location in
                selectedLocation = location
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            PrayerTimesView(selectedLocation: selectedLocation)
                .frame(minWidth: 400, minHeight: 300)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            toggleSidebar()
        }
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