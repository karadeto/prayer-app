//
//  ErrorHandlingViews.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI

// MARK: - Error Alert View

struct ErrorAlertView: View {
    let error: PrayerAppError
    let strategy: ErrorRecoveryStrategy
    let onAction: (ErrorRecoveryAction) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Error Icon and Title
            HStack(spacing: 12) {
                Image(systemName: error.severity.icon)
                    .font(.title2)
                    .foregroundColor(error.severity.color)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(error.category.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Error Description
            VStack(alignment: .leading, spacing: 8) {
                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                // Secondary actions
                ForEach(strategy.secondaryActions, id: \.self) { action in
                    Button(action.title) {
                        onAction(action)
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                // Primary action
                Button(strategy.primaryAction.title) {
                    onAction(strategy.primaryAction)
                }
                .buttonStyle(.borderedProminent)
                .foregroundColor(strategy.primaryAction.isDestructive ? .red : .accentColor)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 8)
    }
}

// MARK: - Error Banner View

struct ErrorBannerView: View {
    let error: PrayerAppError
    let onDismiss: () -> Void
    let onAction: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.severity.icon)
                .foregroundColor(error.severity.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.category.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button("Fix") {
                onAction()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(error.severity.color.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(width: 4)
                .foregroundColor(error.severity.color),
            alignment: .leading
        )
        .cornerRadius(8)
        .scaleEffect(isVisible ? 1 : 0.8)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.3), value: isVisible)
        .onAppear {
            isVisible = true
        }
    }
}

// MARK: - Degraded Mode Banner

struct DegradedModeBannerView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            
            Text(message)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(width: 4)
                .foregroundColor(.orange),
            alignment: .leading
        )
        .cornerRadius(8)
    }
}

// MARK: - Error Recovery Progress View

struct ErrorRecoveryProgressView: View {
    let error: PrayerAppError
    let attempt: Int
    let maxAttempts: Int
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Attempting to recover...")
                .font(.body)
                .foregroundColor(.primary)
            
            Text("Attempt \(attempt) of \(maxAttempts)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 4)
    }
}

// MARK: - Error Log View

struct ErrorLogView: View {
    @State private var errorEntries: [ErrorLogEntry] = []
    @State private var selectedCategory: ErrorCategory?
    @State private var selectedSeverity: ErrorSeverity?
    @State private var showingExportSheet = false
    @State private var exportText = ""
    
    var filteredEntries: [ErrorLogEntry] {
        var entries = errorEntries
        
        if let category = selectedCategory {
            entries = entries.filter { $0.error.category == category }
        }
        
        if let severity = selectedSeverity {
            entries = entries.filter { $0.error.severity == severity }
        }
        
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with filters
            HStack {
                Text("Error Log")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Category filter
                Picker("Category", selection: $selectedCategory) {
                    Text("All Categories").tag(nil as ErrorCategory?)
                    ForEach([ErrorCategory.network, .location, .notifications, .data, .prayerTimes, .system], id: \.self) { category in
                        Text(category.displayName).tag(category as ErrorCategory?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                
                // Severity filter
                Picker("Severity", selection: $selectedSeverity) {
                    Text("All Severities").tag(nil as ErrorSeverity?)
                    Text("Critical").tag(ErrorSeverity.critical as ErrorSeverity?)
                    Text("Error").tag(ErrorSeverity.error as ErrorSeverity?)
                    Text("Warning").tag(ErrorSeverity.warning as ErrorSeverity?)
                    Text("Info").tag(ErrorSeverity.info as ErrorSeverity?)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                
                Button("Export") {
                    exportLogs()
                }
                .buttonStyle(.bordered)
                
                Button("Clear") {
                    clearLogs()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            // Error list
            if filteredEntries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    
                    Text("No errors found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Your app is running smoothly!")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEntries, id: \.id) { entry in
                    ErrorLogEntryView(entry: entry)
                }
            }
        }
        .onAppear {
            loadErrorEntries()
        }
        .sheet(isPresented: $showingExportSheet) {
            NavigationView {
                ScrollView {
                    Text(exportText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("Error Log Export")
                .navigationTitle("Error Details")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            showingExportSheet = false
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(exportText, forType: .string)
                        }
                    }
                }
            }
        }
    }
    
    private func loadErrorEntries() {
        errorEntries = ErrorLogger.shared.getRecentErrors(limit: 100)
    }
    
    private func exportLogs() {
        exportText = ErrorLogger.shared.exportLogsForDebug()
        showingExportSheet = true
    }
    
    private func clearLogs() {
        ErrorLogger.shared.clearLogs()
        loadErrorEntries()
    }
}

// MARK: - Error Log Entry View

struct ErrorLogEntryView: View {
    let entry: ErrorLogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entry.error.severity.icon)
                    .foregroundColor(entry.error.severity.color)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.error.localizedDescription ?? "Unknown error")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text(entry.error.category.displayName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(entry.error.severity.color.opacity(0.2))
                            .cornerRadius(4)
                        
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let userAction = entry.context?.userAction {
                        Text("User Action: \(userAction)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Location: \(entry.file):\(entry.line) in \(entry.function)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let suggestion = entry.error.recoverySuggestion {
                        Text("Suggestion: \(suggestion)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Error Handling View Modifier

struct ErrorHandlingViewModifier: ViewModifier {
    @ObservedObject private var errorHandler = ErrorHandlerManager.shared
    @ObservedObject private var degradationManager = GracefulDegradationManager.shared
    @State private var showingDegradedBanner = false
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            VStack {
                // Degraded mode banner
                if let message = degradationManager.getDegradedModeMessage(),
                   showingDegradedBanner {
                    DegradedModeBannerView(message: message) {
                        showingDegradedBanner = false
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
            }
        }
        .alert("Error", isPresented: $errorHandler.isShowingError) {
            if let strategy = errorHandler.errorRecoveryStrategy {
                // Primary action
                Button(strategy.primaryAction.title) {
                    errorHandler.executeRecoveryAction(strategy.primaryAction)
                }
                
                // Secondary actions
                ForEach(strategy.secondaryActions, id: \.self) { action in
                    Button(action.title, role: action.isDestructive ? .destructive : nil) {
                        errorHandler.executeRecoveryAction(action)
                    }
                }
            }
        } message: {
            if let error = errorHandler.currentError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription)
                    
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                    }
                }
            }
        }
        .onAppear {
            degradationManager.updateFeatureAvailability()
            showingDegradedBanner = degradationManager.shouldShowDegradedModeWarning()
        }
        .onReceive(NotificationCenter.default.publisher(for: .networkStatusChanged)) { _ in
            degradationManager.updateFeatureAvailability()
            showingDegradedBanner = degradationManager.shouldShowDegradedModeWarning()
        }
    }
}

// MARK: - View Extension

extension View {
    func withErrorHandling() -> some View {
        modifier(ErrorHandlingViewModifier())
    }
}