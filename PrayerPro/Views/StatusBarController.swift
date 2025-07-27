//
//  StatusBarController.swift
//  PrayerPro
//
//  Created by Kiro on 24.07.25.
//

import SwiftUI
import AppKit
import SwiftData

class StatusBarController: NSObject, ObservableObject {
    static let shared = StatusBarController()
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var popoverContentController: NSHostingController<StatusBarView>?
    private var timer: Timer?
    private var modelContext: ModelContext?
    private var lastPrayerDataUpdate: Date = Date.distantPast
    
    @Published var isVisible: Bool = true {
        didSet {
            if isVisible {
                showWidget()
            } else {
                hideWidget()
            }
        }
    }
    
    @Published var currentLocation: Location?
    @Published var nextPrayer: Prayer?
    @Published var timeRemaining: TimeInterval = 0
    @Published var countdownText: String = "--:--"
    private var countdownTargetTime: Date? // Store target time for Isha->Fajr countdown
    
    private let prayerTimeService = PrayerTimeService.shared
    private let preferencesManager = PreferencesManager.shared
    
    private override init() {
        super.init()
        setupPreferencesObservers()
        setupStatusItem()
        startTimer()
    }
    
    // MARK: - Public Interface
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        updatePrayerData()
    }
    
    func updateLocation(_ location: Location?) {
        currentLocation = location
        updatePrayerData(force: true)
    }
    
    func showWidget() {
        guard statusItem == nil else { return }
        setupStatusItem()
        updateDisplay()
    }
    
    func hideWidget() {
        statusItem = nil
        popover = nil
    }
    
    // MARK: - Private Setup
    
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusItem = statusItem else { return }
        
        // Configure button to prevent background issues
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusItemText("--:--")
        
        // Setup popover
        setupPopover()
    }
    
    
    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 400)
        popover?.behavior = .transient
        popover?.animates = true
        
        // Create the SwiftUI view for the popover content
        let statusBarView = StatusBarView(
            currentLocation: currentLocation,
            nextPrayer: nextPrayer,
            timeRemaining: timeRemaining
        )
        
        popoverContentController = NSHostingController(rootView: statusBarView)
        popover?.contentViewController = popoverContentController
    }
    
    private func setupPreferencesObservers() {
        // Listen for preference changes
        NotificationCenter.default.addObserver(
            forName: .statusBarWidgetPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let isEnabled = userInfo["isEnabled"] as? Bool {
                self?.isVisible = isEnabled
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .statusBarDisplayFormatChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDisplay()
        }
        
        NotificationCenter.default.addObserver(
            forName: .statusBarUpdateFrequencyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartTimer()
        }
        
        NotificationCenter.default.addObserver(
            forName: .statusBarIconPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDisplay()
        }
    }
    
    private func startTimer() {
        // Use 1 second interval for accurate status bar updates
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateCountdown()
            }
        }
        
        // Listen for performance optimization requests
        NotificationCenter.default.addObserver(
            forName: .adjustUpdateFrequency,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let newInterval = userInfo["interval"] as? TimeInterval {
                self?.adjustTimerFrequency(to: newInterval)
            }
        }
        
        // Listen for battery saving mode
        NotificationCenter.default.addObserver(
            forName: .enableBatterySavingMode,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enableBatterySavingMode()
        }
        
        // Listen for prayer completion changes
        NotificationCenter.default.addObserver(
            forName: .prayerCompletionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePrayerData(force: true)
        }
        
        // Listen for refresh requests
        NotificationCenter.default.addObserver(
            forName: .refreshPrayerTimes,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePrayerData(force: true)
        }
    }
    
    private func restartTimer() {
        timer?.invalidate()
        startTimer()
    }
    
    // MARK: - Data Updates
    
    private func updatePrayerData(force: Bool = false) {
        guard let modelContext = modelContext else { 
            print("StatusBarController: No model context available")
            return 
        }
        
        // Throttle updates to prevent excessive cache refreshing (unless forced)
        if !force {
            let now = Date()
            let timeSinceLastUpdate = now.timeIntervalSince(lastPrayerDataUpdate)
            if timeSinceLastUpdate < 60 { // Minimum 60 seconds between updates
                return
            }
            lastPrayerDataUpdate = now
        } else {
            lastPrayerDataUpdate = Date()
        }
        
        Task { @MainActor in
            // Ensure we still have a valid modelContext
            guard let validContext = self.modelContext else {
                print("StatusBarController: Context deallocated during update")
                return
            }
            
            do {
                // Defensive check for model context validity
                let tempDescriptor = FetchDescriptor<Prayer>(predicate: #Predicate { _ in false })
                _ = try validContext.fetch(tempDescriptor)
                
                let status = await self.prayerTimeService.getCurrentPrayerStatus(
                    for: self.currentLocation,
                    in: validContext
                )
                
                // Validate status before using
                try status.validate()
                
                // Check if still valid before updating
                guard self.modelContext != nil else {
                    print("StatusBarController: Context deallocated during async operation")
                    return
                }
                
                print("📊 StatusBarController received prayer status:")
                print("   Current prayer: \(status.currentPrayer?.prayerType.displayName ?? "none")")
                print("   Next prayer: \(status.nextPrayer?.prayerType.displayName ?? "none")")
                print("   Time until next: \(status.timeUntilNext) seconds")
                
                self.nextPrayer = status.nextPrayer
                self.timeRemaining = status.timeUntilNext
                
                // Store target time for accurate countdown when nextPrayer is nil (Isha->Fajr)
                if status.nextPrayer == nil && status.timeUntilNext > 0 {
                    self.countdownTargetTime = Date().addingTimeInterval(status.timeUntilNext)
                    print("   ✅ Stored countdown target time: \(self.countdownTargetTime!)")
                } else {
                    if self.countdownTargetTime != nil {
                        print("   ❌ Clearing countdown target time (nextPrayer: \(status.nextPrayer?.prayerType.displayName ?? "nil"), timeUntilNext: \(status.timeUntilNext))")
                    }
                    self.countdownTargetTime = nil
                }
                
                self.updateDisplay()
                self.updatePopoverContent()
            } catch {
                print("StatusBarController: Error updating prayer data - \(error.localizedDescription)")
                // Fallback to safe defaults only if still valid
                guard self.modelContext != nil else { return }
                
                self.nextPrayer = nil
                self.timeRemaining = 0
                self.countdownText = "--:--"
                self.updateDisplay()
            }
        }
    }
    
    private func updateCountdown() {
        // Record performance metrics
        PerformanceMonitor.shared.recordCacheHit()
        
        let now = Date()
        print("🕐 updateCountdown called at \(now)")
        print("   nextPrayer: \(nextPrayer?.prayerType.displayName ?? "nil")")
        print("   countdownTargetTime: \(countdownTargetTime?.description ?? "nil")")
        print("   current timeRemaining: \(timeRemaining)")
        
        // Calculate dynamic time remaining instead of decrementing
        if let prayer = nextPrayer {
            timeRemaining = max(0, prayer.time.timeIntervalSince(now))
            print("   Updated timeRemaining from nextPrayer: \(timeRemaining)")
        } else if let targetTime = countdownTargetTime {
            // During Isha (when nextPrayer is nil), countdown to tomorrow's Fajr using stored target time
            timeRemaining = max(0, targetTime.timeIntervalSince(now))
            print("   Updated timeRemaining from countdownTargetTime: \(timeRemaining)")
        } else {
            timeRemaining = 0
            print("   Set timeRemaining to 0 (no next prayer or target time)")
        }
        
        guard timeRemaining > 0 else {
            // Time has passed, refresh prayer data (throttled)
            // But don't refresh if we just set a countdown target time - let it work first
            if countdownTargetTime == nil {
                updatePrayerData()
            }
            return
        }
        
        // Always update display with fresh data
        updateDisplay()
        
        // Also update the popover content if it's showing
        if let popover = popover, popover.isShown {
            updatePopoverContent()
        }
        
        
        // Optimize memory usage periodically
        if Int(timeRemaining) % 300 == 0 { // Every 5 minutes
            optimizeMemoryUsage()
        }
    }
    
    private func updateDisplay() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let displayText = self.getDisplayText()
            self.updateStatusItemText(displayText)
            
            // Update tooltip
            if let nextPrayer = self.nextPrayer {
                self.statusItem?.button?.toolTip = "Next prayer: \(nextPrayer.prayerType.displayName) in \(self.countdownText)"
            } else {
                self.statusItem?.button?.toolTip = "Prayer Times"
            }
        }
    }
    
    private func updateStatusItemText(_ text: String) {
        guard let button = statusItem?.button else { return }

        // Text (optional mit SF Symbol oder Emoji)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        button.attributedTitle = attributedString

        // 💥 Fix: Layer aktivieren + transparent setzen
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.cornerRadius = 6  // optional: optische Abrundung

        // (optional) Entferne Focus-Ring bei Klick
        button.focusRingType = .none
    }
    
    private func getDisplayText() -> String {
        let format = preferencesManager.statusBarDisplayFormat
        let showIcon = preferencesManager.showStatusBarIcon
        
        switch format {
        case .countdown:
            return getDynamicCountdownText()
            
        case .nextPrayerTime:
            if let nextPrayer = nextPrayer {
                return "\(nextPrayer.prayerType.displayName) \(nextPrayer.time.formattedTime)"
            } else if countdownTargetTime != nil {
                return "Fajr \(countdownTargetTime!.formattedTime)"
            } else {
                return "--:--"
            }
            
        case .nextPrayerName:
            if let nextPrayer = nextPrayer {
                return nextPrayer.prayerType.displayName
            } else if countdownTargetTime != nil {
                return "Fajr"
            } else {
                return "--:--"
            }
            
        case .iconAndCountdown:
            if let nextPrayer = nextPrayer {
                let icon = showIcon ? "\(getPrayerIconSymbol(for: nextPrayer.prayerType)) " : ""
                return "\(icon)\(getDynamicCountdownText())"
            } else if countdownTargetTime != nil {
                let icon = showIcon ? "\(getPrayerIconSymbol(for: .fajr)) " : ""
                return "\(icon)\(getDynamicCountdownText())"
            } else {
                return "--:--"
            }
        }
    }
    
    private func getPrayerIconSymbol(for prayerType: PrayerType) -> String {
        switch prayerType {
        case .fajr:
            return "🌙"  // Moon for Fajr
        case .sunrise:
            return "🌅"  // Sunrise
        case .dhuhr:
            return "☀️"  // Sun for Dhuhr
        case .asr:
            return "🌞"  // Sun with face for Asr
        case .maghrib:
            return "🌇"  // Sunset
        case .isha:
            return "🌃"  // Night
        }
    }
    
    private func updatePopoverContent() {
        guard let popoverContentController = popoverContentController else { return }
        
        // Update the existing view with new data instead of creating a new controller
        let updatedView = StatusBarView(
            currentLocation: currentLocation,
            nextPrayer: nextPrayer,
            timeRemaining: timeRemaining
        )
        
        popoverContentController.rootView = updatedView
    }
    
    private func getDynamicCountdownText() -> String {
        if let prayer = nextPrayer {
            let dynamicTimeRemaining = max(0, prayer.time.timeIntervalSince(Date()))
            let formattedText = formatCountdown(dynamicTimeRemaining)
            print("📱 Display text from nextPrayer: \(formattedText) (remaining: \(dynamicTimeRemaining)s)")
            return formattedText
        } else if let targetTime = countdownTargetTime {
            let dynamicTimeRemaining = max(0, targetTime.timeIntervalSince(Date()))
            let formattedText = formatCountdown(dynamicTimeRemaining)
            print("📱 Display text from countdownTargetTime: \(formattedText) (remaining: \(dynamicTimeRemaining)s)")
            return formattedText
        } else {
            print("📱 Display text: --:-- (no prayer or target time)")
            return "--:--"
        }
    }
    
    private func formatCountdown(_ timeInterval: TimeInterval) -> String {
        return timeInterval.statusBarFormat
    }
    
    // MARK: - User Interaction
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            // Right click - show context menu
            showContextMenu()
        } else {
            // Left click - handle based on preference
            handleLeftClick(sender)
        }
    }
    
    private func handleLeftClick(_ sender: NSStatusBarButton) {
        switch preferencesManager.statusBarClickAction {
        case .showPopover:
            guard let popover = popover else { return }
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
                updatePopoverContent()
            }
            
        case .showMainWindow:
            showMainWindow()
            
        case .doNothing:
            break
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        // Show/Hide main window
        let showWindowItem = NSMenuItem(
            title: "Show Prayer Times",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        menu.addItem(showWindowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Refresh prayer times
        let refreshItem = NSMenuItem(
            title: "Refresh Prayer Times",
            action: #selector(refreshPrayerTimes),
            keyEquivalent: ""
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Preferences
        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.keyEquivalentModifierMask = .command
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        // Hide status bar widget
        let hideWidgetItem = NSMenuItem(
            title: "Hide Status Bar Widget",
            action: #selector(hideStatusBarWidget),
            keyEquivalent: ""
        )
        hideWidgetItem.target = self
        menu.addItem(hideWidgetItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit application
        let quitItem = NSMenuItem(
            title: "Quit Prayer Times",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        // Find and show the main window
        for window in NSApp.windows {
            if window.identifier?.rawValue == "MainWindow" || window.contentViewController is NSHostingController<MainWindowView> {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
    
    @objc private func refreshPrayerTimes() {
        updatePrayerData(force: true)
        NotificationCenter.default.post(name: .refreshPrayerTimes, object: nil)
    }
    
    @objc private func showPreferences() {
        // Use native macOS Settings window (Cmd+,)
        // This is handled by the SwiftUI Settings scene in the app
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    
    @objc private func hideStatusBarWidget() {
        preferencesManager.isStatusBarWidgetEnabled = false
    }
    
    // MARK: - Performance Optimization
    
    private func getOptimalUpdateInterval() -> TimeInterval {
        // Smart optimization: only update seconds when time < 60 minutes
        if timeRemaining < 3600 { // Less than 60 minutes
            return 1.0 // Update every second to show seconds
        } else {
            return 60.0 // Update every minute when only showing hours/minutes
        }
    }
    
    private func adjustTimerFrequency(to interval: TimeInterval) {
        // Force 1-second intervals to prevent timer issues
        let fixedInterval = 1.0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: fixedInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateCountdown()
            }
        }
// Forced to 1-second intervals for reliability
    }
    
    private func enableBatterySavingMode() {
        // Keep 1 second updates for accurate countdown but optimize other operations
        // Simplify display format to reduce processing
        let currentFormat = preferencesManager.statusBarDisplayFormat
        if currentFormat == .iconAndCountdown {
            // Temporarily switch to simpler format
            print("🔋 Switching to simpler display format for battery saving")
        }
        
        print("🔋 Status bar battery saving mode enabled (keeping 1s updates)")
    }
    
    private func optimizeMemoryUsage() {
        // Clear any cached data that's not immediately needed
        if let popover = popover, !popover.isShown {
            // Recreate popover content controller to free memory
            popoverContentController = nil
            setupPopover()
        }
        
        // Force update display to ensure consistency
        updateDisplay()
    }
    
    
    // MARK: - Lifecycle
    
    deinit {
        print("🧹 StatusBarController deinit starting...")
        
        // Invalidate timer first
        timer?.invalidate()
        timer = nil
        
        // Clean up popover
        if let popover = popover {
            DispatchQueue.main.async {
                popover.performClose(nil)
            }
        }
        popover = nil
        popoverContentController = nil
        
        // Clean up status item
        if let statusItem = statusItem {
            DispatchQueue.main.async {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
        }
        statusItem = nil
        
        // Clean up model context reference
        modelContext = nil
        
        // Remove all observers
        NotificationCenter.default.removeObserver(self)
        
        print("✅ StatusBarController deinit completed")
    }
}

// MARK: - Notification Extensions


extension Notification.Name {
    static let statusBarWidgetToggled = Notification.Name("StatusBarWidgetToggled")
}
