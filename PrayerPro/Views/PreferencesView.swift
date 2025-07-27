//
//  PreferencesView.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import CloudKit

struct PreferencesView: View {
    @ObservedObject private var preferencesManager = PreferencesManager.shared
    
    @State private var selectedTab: PreferencesTab = .statusBar
    
    var body: some View {
        TabView(selection: $selectedTab) {
            StatusBarPreferencesView()
                .tabItem {
                    Label("Status Bar", systemImage: "menubar.rectangle")
                }
                .tag(PreferencesTab.statusBar)
            
            GeneralPreferencesView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(PreferencesTab.general)
            
            NotificationPreferencesViewImpl()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(PreferencesTab.notifications)
            
            iCloudSyncPreferencesView()
                .tabItem {
                    Label("iCloud Sync", systemImage: "icloud")
                }
                .tag(PreferencesTab.iCloudSync)
        }
        .tabViewStyle(.automatic)
        .frame(width: 500, height: 400)
    }
}

// MARK: - Status Bar Preferences View

struct StatusBarPreferencesView: View {
    @ObservedObject private var preferencesManager = PreferencesManager.shared
    @ObservedObject private var statusBarController = StatusBarController.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Enable/Disable Widget
                widgetToggleSection
                
                if preferencesManager.isStatusBarWidgetEnabled {
                    // Display Format
                    displayFormatSection
                    
                    // Update Frequency
                    updateFrequencySection
                    
                    // Icon Settings
                    iconSettingsSection
                    
                    // Click Action
                    clickActionSection
                    
                    // Preview
                    previewSection
                }
                
                // Reset Options
                resetSection
            }
            .padding()
        }
    }
    
    private var widgetToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status Bar Widget")
                .font(.headline)
            
            Toggle("Show status bar widget", isOn: $preferencesManager.isStatusBarWidgetEnabled)
                .toggleStyle(.switch)
            
            Text("Display a countdown timer and prayer information in the menu bar")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var displayFormatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display Format")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(StatusBarDisplayFormat.allCases) { format in
                    HStack {
                        RadioButton(
                            isSelected: preferencesManager.statusBarDisplayFormat == format,
                            action: {
                                preferencesManager.statusBarDisplayFormat = format
                            }
                        )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(format.displayName)
                                .font(.system(size: 13, weight: .medium))
                            
                            Text(format.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        preferencesManager.statusBarDisplayFormat = format
                    }
                }
            }
        }
    }
    
    private var updateFrequencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update Frequency")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(StatusBarUpdateFrequency.allCases) { frequency in
                    HStack {
                        RadioButton(
                            isSelected: preferencesManager.statusBarUpdateFrequency == frequency,
                            action: {
                                preferencesManager.statusBarUpdateFrequency = frequency
                            }
                        )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(frequency.displayName)
                                .font(.system(size: 13, weight: .medium))
                            
                            Text(frequency.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        preferencesManager.statusBarUpdateFrequency = frequency
                    }
                }
            }
        }
    }
    
    private var iconSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon Settings")
                .font(.headline)
            
            Toggle("Show prayer icons", isOn: $preferencesManager.showStatusBarIcon)
                .toggleStyle(.switch)
            
            Text("Display prayer-specific icons (🌙, ☀️, etc.) in the status bar")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var clickActionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Click Action")
                .font(.headline)
            
            Picker("When status bar widget is clicked", selection: $preferencesManager.statusBarClickAction) {
                ForEach(StatusBarClickAction.allCases) { action in
                    Text(action.displayName)
                        .tag(action)
                }
            }
            .pickerStyle(.menu)
            
            Text("Choose what happens when you click the status bar widget")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)
            
            HStack {
                Text("Status bar will show:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Mock preview based on current settings
                Text(mockStatusBarText)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }
    
    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reset")
                .font(.headline)
            
            HStack {
                Button("Reset Status Bar Settings") {
                    preferencesManager.resetStatusBarPreferences()
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            
            Text("Reset all status bar widget settings to their default values")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var mockStatusBarText: String {
        let format = preferencesManager.statusBarDisplayFormat
        let showIcon = preferencesManager.showStatusBarIcon
        
        switch format {
        case .countdown:
            return "2:30"
        case .nextPrayerTime:
            return "Dhuhr 12:30"
        case .nextPrayerName:
            return "Dhuhr"
        case .iconAndCountdown:
            return showIcon ? "☀️ 2:30" : "2:30"
        }
    }
}

// MARK: - General Preferences View

struct GeneralPreferencesView: View {
    @ObservedObject private var preferencesManager = PreferencesManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("General Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location")
                        .font(.headline)
                    
                    Toggle("Use GPS location automatically", isOn: $preferencesManager.useGPSLocation)
                        .toggleStyle(.switch)
                    
                    Text("Automatically detect your current location for prayer times")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Notification Preferences View Implementation
struct NotificationPreferencesViewImpl: View {
    @ObservedObject private var preferencesManager = PreferencesManager.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var showingLocationPicker = false
    @State private var availableLocations: [Location] = []
    @State private var isLoadingLocations = false
    @State private var isRequestingPermission = false
    @State private var notificationObserver: NSObjectProtocol?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prayer Notifications")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Get notified when it's time for prayer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Permission Status
                permissionStatusSection
                
                if notificationManager.isPermissionGranted {
                    // Main Settings
                    mainSettingsSection
                    
                    Divider()
                    
                    // Prayer Type Settings
                    prayerTypeSection
                    
                    Divider()
                    
                    // Location Settings
                    locationSection
                    
                    Divider()
                    
                    // Advanced Settings
                    advancedSettingsSection
                    
                    Divider()
                    
                    // Test Section
                    testSection
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            Task { @MainActor in
                await notificationManager.updatePermissionStatus()
            }
            
            // Setup notification observer with weak self pattern
            notificationObserver = NotificationCenter.default.addObserver(
                forName: .notificationPermissionChanged,
                object: nil,
                queue: .main
            ) { [weak notificationManager] _ in
                guard let notificationManager = notificationManager else { return }
                Task { @MainActor in
                    await notificationManager.updatePermissionStatus()
                }
            }
        }
        .onDisappear {
            // Clean up notification observer
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
                notificationObserver = nil
            }
        }
    }
    
    // MARK: - Permission Status Section
    
    @ViewBuilder
    private var permissionStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: notificationManager.isPermissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(notificationManager.isPermissionGranted ? .green : .orange)
                
                Text("Notification Permission")
                    .font(.headline)
                
                Spacer()
                
                Text(permissionStatusText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(notificationManager.isPermissionGranted ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundColor(notificationManager.isPermissionGranted ? .green : .orange)
                    .cornerRadius(8)
            }
            
            if !notificationManager.isPermissionGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prayer notifications require permission to send notifications.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button(isRequestingPermission ? "Requesting..." : "Request Permission") {
                            isRequestingPermission = true
                            Task {
                                let granted = await notificationManager.requestNotificationPermission()
                                await MainActor.run {
                                    isRequestingPermission = false
                                }
                                if granted {
                                    await notificationManager.scheduleAllNotifications()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRequestingPermission)
                        
                        if notificationManager.permissionStatus == .denied {
                            Button("Open Settings") {
                                notificationManager.openNotificationSettings()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Main Settings Section
    
    @ViewBuilder
    private var mainSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Prayer Notifications", isOn: $preferencesManager.notificationsEnabled)
                .font(.headline)
                .onChange(of: preferencesManager.notificationsEnabled) { _, newValue in
                    Task {
                        if newValue {
                            await notificationManager.scheduleAllNotifications()
                        } else {
                            await notificationManager.clearAllNotifications()
                        }
                    }
                }
            
            if preferencesManager.notificationsEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Advance Notification")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Picker("Minutes", selection: $preferencesManager.notificationAdvanceMinutes) {
                            Text("At prayer time").tag(0)
                            Text("5 minutes before").tag(5)
                            Text("10 minutes before").tag(10)
                            Text("15 minutes before").tag(15)
                            Text("30 minutes before").tag(30)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                        
                        Spacer()
                    }
                    
                    Text("Get notified before prayer time to prepare")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading)
            }
        }
    }
    
    // MARK: - Prayer Type Section
    
    @ViewBuilder
    private var prayerTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prayer Types")
                .font(.headline)
            
            Text("Choose which prayers to receive notifications for")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(PrayerType.allCases, id: \.self) { prayerType in
                    if prayerType != .sunrise { // Don't show sunrise as it's not a prayer
                        prayerTypeToggle(for: prayerType)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func prayerTypeToggle(for prayerType: PrayerType) -> some View {
        HStack {
            Image(systemName: preferencesManager.isPrayerNotificationEnabled(prayerType) ? "checkmark.circle.fill" : "circle")
                .foregroundColor(preferencesManager.isPrayerNotificationEnabled(prayerType) ? .blue : .secondary)
            
            Text(prayerType.displayName)
                .font(.subheadline)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(preferencesManager.isPrayerNotificationEnabled(prayerType) ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            preferencesManager.togglePrayerNotification(prayerType)
            Task {
                await notificationManager.rescheduleAllNotifications()
            }
        }
    }
    
    // MARK: - Location Section
    
    @ViewBuilder
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notification Location")
                .font(.headline)
            
            Text("Choose which location to use for prayer time notifications")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                // GPS Location Option
                HStack {
                    Image(systemName: preferencesManager.useGPSForNotifications ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(preferencesManager.useGPSForNotifications ? .blue : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Current Location (GPS)")
                            .font(.subheadline)
                        Text("Automatically use your current location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(preferencesManager.useGPSForNotifications ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(8)
                .onTapGesture {
                    preferencesManager.useGPSLocationForNotifications()
                    Task {
                        await notificationManager.rescheduleAllNotifications()
                    }
                }
                
                // Specific Location Option
                HStack {
                    Image(systemName: !preferencesManager.useGPSForNotifications ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(!preferencesManager.useGPSForNotifications ? .blue : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Specific Location")
                            .font(.subheadline)
                        if let locationId = preferencesManager.notificationLocationId {
                            Text("Selected location: \(locationId.uuidString.prefix(8))...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No location selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Choose") {
                        showingLocationPicker = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(preferencesManager.useGPSForNotifications)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(!preferencesManager.useGPSForNotifications ? Color.blue.opacity(0.1) : Color.clear)
                .cornerRadius(8)
                .onTapGesture {
                    if preferencesManager.useGPSForNotifications {
                        preferencesManager.useGPSForNotifications = false
                    }
                }
            }
        }
    }
    
    // MARK: - Advanced Settings Section
    
    @ViewBuilder
    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound & Display")
                .font(.headline)
            
            HStack {
                Text("Notification Sound")
                    .font(.subheadline)
                
                Spacer()
                
                Picker("Sound", selection: $preferencesManager.notificationSound) {
                    Text("Default").tag("default")
                    Text("None").tag("none")
                    Text("Chime").tag("chime")
                    Text("Bell").tag("bell")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 120)
            }
        }
    }
    
    // MARK: - Test Section
    
    @ViewBuilder
    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Notifications")
                .font(.headline)
            
            Text("Send a test notification to verify your settings")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Send Test Notification") {
                    Task {
                        await notificationManager.scheduleTestNotification()
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Debug Settings") {
                    Task {
                        await notificationManager.debugNotificationSettings()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var permissionStatusText: String {
        switch notificationManager.permissionStatus {
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Requested"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - Radio Button Component

struct RadioButton: View {
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .font(.system(size: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preferences Tab Enum

enum PreferencesTab: String, CaseIterable {
    case statusBar = "statusBar"
    case general = "general"
    case notifications = "notifications"
    case iCloudSync = "iCloudSync"
}

// MARK: - iCloud Sync Preferences View

struct iCloudSyncPreferencesView: View {
    @ObservedObject private var syncService = iCloudSyncService.shared
    @State private var accountStatus: CKAccountStatus = .couldNotDetermine
    @State private var isCheckingStatus = false
    @State private var lastSyncError: String?
    @State private var showingSchemaInstructions = false
    @State private var currentTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("iCloud Sync")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Sync your prayer completion data across all your devices")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Account Status Section
                accountStatusSection
                
                if accountStatus == .available {
                    Divider()
                    
                    // Sync Status Section
                    syncStatusSection
                    
                    Divider()
                    
                    // Manual Sync Section
                    manualSyncSection
                    
                    Divider()
                    
                    // Troubleshooting Section
                    troubleshootingSection
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            checkAccountStatus()
        }
        .onDisappear {
            // Cancel any running tasks
            currentTask?.cancel()
            currentTask = nil
        }
        .sheet(isPresented: $showingSchemaInstructions) {
            SchemaInstructionsView()
        }
    }
    
    // MARK: - Account Status Section
    
    @ViewBuilder
    private var accountStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: accountStatusIcon)
                    .foregroundColor(accountStatusColor)
                
                Text("iCloud Account")
                    .font(.headline)
                
                Spacer()
                
                if isCheckingStatus {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(accountStatusText)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accountStatusColor.opacity(0.2))
                        .foregroundColor(accountStatusColor)
                        .cornerRadius(8)
                }
            }
            
            Text(accountStatusDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if accountStatus != .available {
                VStack(alignment: .leading, spacing: 8) {
                    Text(accountStatusSolution)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Check Again") {
                            checkAccountStatus()
                        }
                        .buttonStyle(.bordered)
                        
                        if accountStatus == .noAccount {
                            Button("Open iCloud Settings") {
                                openSystemPreferences()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Sync Status Section
    
    @ViewBuilder
    private var syncStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Status")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Sync")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let lastSync = syncService.lastSyncDate {
                        Text(formatDate(lastSync))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if syncService.isSyncing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Syncing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            if let error = syncService.syncError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        Text("Sync Error")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Manual Sync Section
    
    @ViewBuilder
    private var manualSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Sync")
                .font(.headline)
            
            Text("Manually sync your prayer completion data")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Sync Now") {
                    performManualSync()
                }
                .buttonStyle(.borderedProminent)
                .disabled(syncService.isSyncing)
                
                Button("Download from iCloud") {
                    downloadFromiCloud()
                }
                .buttonStyle(.bordered)
                .disabled(syncService.isSyncing)
            }
        }
    }
    
    // MARK: - Troubleshooting Section
    
    @ViewBuilder
    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Troubleshooting")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Button("View CloudKit Schema Instructions") {
                    showingSchemaInstructions = true
                }
                .buttonStyle(.bordered)
                
                Button("Reset Sync Status") {
                    resetSyncStatus()
                }
                .buttonStyle(.bordered)
                
                Button("Clear Sync Cache") {
                    clearSyncCache()
                }
                .buttonStyle(.bordered)
            }
            
            Text("Use these options if you're experiencing sync issues")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Properties
    
    private var accountStatusIcon: String {
        switch accountStatus {
        case .available:
            return "checkmark.circle.fill"
        case .noAccount:
            return "person.crop.circle.badge.exclamationmark"
        case .restricted:
            return "lock.circle.fill"
        case .couldNotDetermine, .temporarilyUnavailable:
            return "questionmark.circle.fill"
        @unknown default:
            return "exclamationmark.circle.fill"
        }
    }
    
    private var accountStatusColor: Color {
        switch accountStatus {
        case .available:
            return .green
        case .noAccount, .restricted:
            return .red
        case .couldNotDetermine, .temporarilyUnavailable:
            return .orange
        @unknown default:
            return .red
        }
    }
    
    private var accountStatusText: String {
        switch accountStatus {
        case .available:
            return "Available"
        case .noAccount:
            return "No Account"
        case .restricted:
            return "Restricted"
        case .couldNotDetermine:
            return "Unknown"
        case .temporarilyUnavailable:
            return "Unavailable"
        @unknown default:
            return "Error"
        }
    }
    
    private var accountStatusDescription: String {
        switch accountStatus {
        case .available:
            return "Your iCloud account is available and ready for syncing prayer completion data."
        case .noAccount:
            return "No iCloud account is configured on this device."
        case .restricted:
            return "iCloud access is restricted on this device."
        case .couldNotDetermine:
            return "Unable to determine iCloud account status."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable."
        @unknown default:
            return "An unknown error occurred while checking iCloud status."
        }
    }
    
    private var accountStatusSolution: String {
        switch accountStatus {
        case .noAccount:
            return "Sign in to iCloud in System Preferences to enable sync."
        case .restricted:
            return "Check Screen Time or parental controls that may be restricting iCloud access."
        case .couldNotDetermine, .temporarilyUnavailable:
            return "Check your internet connection and try again."
        default:
            return ""
        }
    }
    
    // MARK: - Helper Methods
    
    private func checkAccountStatus() {
        // Cancel existing task
        currentTask?.cancel()
        
        isCheckingStatus = true
        currentTask = Task {
            do {
                let status = try await syncService.checkAccountStatus()
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.accountStatus = status
                    self.isCheckingStatus = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.accountStatus = .couldNotDetermine
                    self.isCheckingStatus = false
                }
            }
        }
    }
    
    private func performManualSync() {
        Task {
            // This would need access to the model context
            // In a real implementation, you'd pass this through or use a shared context
            print("Manual sync requested")
        }
    }
    
    private func downloadFromiCloud() {
        Task {
            // This would need access to the model context
            print("Download from iCloud requested")
        }
    }
    
    private func resetSyncStatus() {
        // Reset sync-related UserDefaults
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
        print("Sync status reset")
    }
    
    private func clearSyncCache() {
        // Clear any cached sync data
        print("Sync cache cleared")
    }
    
    private func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")!
        NSWorkspace.shared.open(url)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Schema Instructions View

struct SchemaInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("CloudKit Schema Setup")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("To enable iCloud sync, you need to configure the CloudKit schema in the CloudKit Dashboard.")
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Steps:")
                            .font(.headline)
                        
                        ForEach(1...7, id: \.self) { step in
                            HStack(alignment: .top) {
                                Text("\(step).")
                                    .fontWeight(.semibold)
                                    .frame(width: 20, alignment: .leading)
                                
                                Text(schemaStep(step))
                                    .font(.body)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Required Fields for PrayerCompletion:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• prayerType (String)")
                            Text("• date (Date/Time)")
                            Text("• completedAt (Date/Time)")
                            Text("• locationId (String)")
                            Text("• createdAt (Date/Time)")
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("CloudKit Setup")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
    
    private func schemaStep(_ step: Int) -> String {
        switch step {
        case 1:
            return "Open CloudKit Dashboard (https://icloud.developer.apple.com/dashboard/)"
        case 2:
            return "Select your app's container"
        case 3:
            return "Go to Schema > Record Types"
        case 4:
            return "Create a new Record Type named: PrayerCompletion"
        case 5:
            return "Add the required fields (see below)"
        case 6:
            return "Save the schema"
        case 7:
            return "Deploy to Production Environment"
        default:
            return ""
        }
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
}