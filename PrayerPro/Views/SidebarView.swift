//
//  SidebarView.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedLocation: Location?
    @State private var gpsLocation: Location?
    @State private var showingLocationSearch = false
    @State private var showingLocationPermissionAlert = false
    @State private var isLoadingGPS = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    private let locationService = LocationService.shared
    private let favoritesManager = FavoriteLocationsManager.shared
    
    // Binding to communicate selected location to parent
    let onLocationSelected: (Location?) -> Void
    
    init(onLocationSelected: @escaping (Location?) -> Void = { _ in }) {
        self.onLocationSelected = onLocationSelected
    }
    
    var body: some View {
        List(selection: $selectedLocation) {
            // GPS Location Section
            gpsLocationSection
            
            // Favorites Section
            favoritesSection
        }
        .navigationTitle("Locations")
        .toolbar {
            ToolbarItem {
                Button(action: {
                    showingLocationSearch = true
                }) {
                    Image(systemName: "plus")
                }
                .help("Add new location")
            }
        }
        .sheet(isPresented: $showingLocationSearch) {
            LocationSearchView { location in
                selectLocation(location)
            }
        }
        .alert("Location Permission Required", isPresented: $showingLocationPermissionAlert) {
            Button("Open Settings") {
                if let settingsUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                    NSWorkspace.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable location services in System Preferences to use GPS location features.")
        }
        .alert("Location Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: selectedLocation) { _, newLocation in
            onLocationSelected(newLocation)
        }
        .onAppear {
            setupFavoritesManager()
            loadGPSLocationIfAvailable()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshPrayerTimes)) { _ in
            if let location = selectedLocation {
                // Refresh current location data
                if location.isGPSLocation {
                    loadGPSLocationIfAvailable()
                }
            }
        }
    }
    
    // MARK: - GPS Location Section
    
    private var gpsLocationSection: some View {
        Section("Current Location") {
            if isLoadingGPS {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Getting location...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if let gpsLocation = gpsLocation {
                LocationRow(
                    location: gpsLocation,
                    isSelected: selectedLocation?.id == gpsLocation.id,
                    showFavoriteButton: false
                ) {
                    selectLocation(gpsLocation)
                }
            } else {
                Button(action: requestGPSLocation) {
                    HStack {
                        Image(systemName: "location")
                            .foregroundColor(.blue)
                        Text("Use Current Location")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Favorites Section
    
    private var favoritesSection: some View {
        Section("Favorites") {
            if favoritesManager.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading favorites...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if favoritesManager.favoriteLocations.isEmpty {
                Text("No favorite locations")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(favoritesManager.favoriteLocations) { location in
                    LocationRow(
                        location: location,
                        isSelected: selectedLocation?.id == location.id,
                        showFavoriteButton: true,
                        isFavorite: true
                    ) {
                        selectLocation(location)
                    } onFavoriteToggle: {
                        Task {
                            await removeFromFavorites(location)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func setupFavoritesManager() {
        favoritesManager.setModelContext(modelContext)
    }
    
    private func selectLocation(_ location: Location) {
        selectedLocation = location
        onLocationSelected(location)
    }
    
    private func requestGPSLocation() {
        Task {
            await MainActor.run {
                isLoadingGPS = true
                errorMessage = nil
            }
            
            // Request permission first
            let hasPermission = await locationService.requestLocationPermission()
            
            if !hasPermission {
                await MainActor.run {
                    isLoadingGPS = false
                    showingLocationPermissionAlert = true
                }
                return
            }
            
            // Get current location
            do {
                let location = try await locationService.getCurrentLocation()
                
                await MainActor.run {
                    self.gpsLocation = location
                    self.isLoadingGPS = false
                    
                    // Auto-select GPS location
                    selectLocation(location)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    self.isLoadingGPS = false
                }
            }
        }
    }
    
    private func loadGPSLocationIfAvailable() {
        // Only load GPS location if we already have permission
        guard locationService.hasLocationPermission else { return }
        
        Task {
            do {
                let location = try await locationService.getCurrentLocation()
                await MainActor.run {
                    self.gpsLocation = location
                }
            } catch {
                // Silently fail - user can manually request GPS location
                print("Failed to load GPS location: \(error.localizedDescription)")
            }
        }
    }
    
    private func removeFromFavorites(_ location: Location) async {
        do {
            try await favoritesManager.removeFromFavorites(location)
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showingError = true
            }
        }
    }
}

// MARK: - Location Row

struct LocationRow: View {
    let location: Location
    let isSelected: Bool
    let showFavoriteButton: Bool
    var isFavorite: Bool = false
    let onSelect: () -> Void
    var onFavoriteToggle: (() -> Void)?
    
    var body: some View {
        HStack {
            // Location Icon
            Image(systemName: location.isGPSLocation ? "location.fill" : "mappin")
                .foregroundColor(location.isGPSLocation ? .blue : .secondary)
                .frame(width: 16)
            
            // Location Info
            VStack(alignment: .leading, spacing: 2) {
                Text(location.displayName)
                    .font(.headline)
                    .lineLimit(1)
                
                if !location.isGPSLocation {
                    Text(location.country)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Favorite Button
            if showFavoriteButton, let onFavoriteToggle = onFavoriteToggle {
                Button(action: onFavoriteToggle) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            
            // Selection Indicator
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        )
    }
}

#Preview {
    NavigationSplitView {
        SidebarView()
    } detail: {
        Text("Select a location")
    }
    .modelContainer(for: [Location.self, Prayer.self])
}