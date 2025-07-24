//
//  LocationSearchView.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import SwiftData

struct LocationSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [Location] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    private let locationService = LocationService.shared
    private let favoritesManager = FavoriteLocationsManager.shared
    
    let onLocationSelected: (Location) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBar
                
                // Content
                if isSearching {
                    loadingView
                        .onAppear { print("🔄 Showing loading view") }
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    emptyStateView
                        .onAppear { print("❌ Showing empty state view - searchResults.count: \(searchResults.count), searchText: '\(searchText)'") }
                } else if !searchResults.isEmpty {
                    searchResultsList
                        .onAppear { print("✅ Showing search results list - searchResults.count: \(searchResults.count)") }
                } else {
                    instructionsView
                        .onAppear { print("📖 Showing instructions view - searchResults.count: \(searchResults.count), searchText: '\(searchText)'") }
                }
            }
            .navigationTitle("Add Location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Search Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search for a city or location", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    performSearch()
                }
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty {
                        searchResults = []
                    } else if newValue.count >= 2 {
                        // Debounce search
                        Task {
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            if searchText == newValue {
                                performSearch()
                            }
                        }
                    }
                }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding()
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Searching locations...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Locations Found",
            systemImage: "location.slash",
            description: Text("Try searching with a different city name or check your spelling")
        )
    }
    
    private var instructionsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Search for Locations")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter a city name to find prayer times for that location")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var searchResultsList: some View {
        List(searchResults) { location in
            LocationSearchRow(
                location: location,
                onSelect: { selectedLocation in
                    onLocationSelected(selectedLocation)
                    dismiss()
                },
                onAddToFavorites: { locationToAdd in
                    Task {
                        await addToFavorites(locationToAdd)
                    }
                }
            )
            .onAppear {
                print("📱 LocationSearchRow appeared for: \(location.displayName)")
            }
        }
        .listStyle(.plain)
        .frame(minHeight: 200) // Ensure minimum height
        .onAppear {
            print("📋 searchResultsList appeared with \(searchResults.count) items")
            for (index, location) in searchResults.enumerated() {
                print("📍 Item \(index): \(location.displayName) (ID: \(location.id))")
            }
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        Task {
            await MainActor.run {
                isSearching = true
                errorMessage = nil
            }
            
            do {
                let results = try await locationService.searchLocations(query: searchText)
                print("🎯 LocationSearchView received \(results.count) results for query: '\(searchText)'")
                
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                    print("📱 UI updated with \(self.searchResults.count) search results")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    self.isSearching = false
                }
            }
        }
    }
    
    private func addToFavorites(_ location: Location) async {
        do {
            try await favoritesManager.addToFavorites(location)
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showingError = true
            }
        }
    }
}

// MARK: - Location Search Row

struct LocationSearchRow: View {
    let location: Location
    let onSelect: (Location) -> Void
    let onAddToFavorites: (Location) -> Void
    
    @State private var isAddingToFavorites = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("\(location.city), \(location.country)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let diyanetId = location.diyanetId {
                    Text("ID: \(diyanetId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Add to Favorites Button
                Button(action: {
                    isAddingToFavorites = true
                    onAddToFavorites(location)
                    
                    // Reset button state after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isAddingToFavorites = false
                    }
                }) {
                    Image(systemName: isAddingToFavorites ? "checkmark" : "heart")
                        .foregroundColor(isAddingToFavorites ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isAddingToFavorites)
                
                // Select Button
                Button("Select") {
                    onSelect(location)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(location)
        }
    }
}

#Preview {
    LocationSearchView { location in
        print("Selected location: \(location.displayName)")
    }
    .modelContainer(for: [Location.self, Prayer.self])
}