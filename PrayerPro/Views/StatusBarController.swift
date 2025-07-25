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
        updatePrayerData()
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
        // Use the preferred update frequency
        let interval = TimeInterval(preferencesManager.statusBarUpdateFrequency.rawValue)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
        
        // Listen for prayer completion changes
        NotificationCenter.default.addObserver(
            forName: .prayerCompletionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePrayerData()
        }
        
        // Listen for refresh requests
        NotificationCenter.default.addObserver(
            forName: .refreshPrayerTimes,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePrayerData()
        }
    }
    
    private func restartTimer() {
        timer?.invalidate()
        startTimer()
    }
    
    // MARK: - Data Updates
    
    private func updatePrayerData() {
        guard let modelContext = modelContext else { 
            print("StatusBarController: No model context available")
            return 
        }
        
        Task { @MainActor in
            do {
                // Defensive check for model context validity
                let tempDescriptor = FetchDescriptor<Prayer>(predicate: #Predicate { _ in false })
                _ = try modelContext.fetch(tempDescriptor)
                
                let status = await prayerTimeService.getCurrentPrayerStatus(
                    for: currentLocation,
                    in: modelContext
                )
                
                // Validate status before using
                try status.validate()
                
                nextPrayer = status.nextPrayer
                timeRemaining = status.timeUntilNext
                
                updateDisplay()
                updatePopoverContent()
            } catch {
                print("StatusBarController: Error updating prayer data - \(error.localizedDescription)")
                // Fallback to safe defaults
                nextPrayer = nil
                timeRemaining = 0
                countdownText = "--:--"
                updateDisplay()
            }
        }
    }
    
    private func updateCountdown() {
        guard timeRemaining > 0 else {
            // Time has passed, refresh prayer data
            updatePrayerData()
            return
        }
        
        timeRemaining -= 1
        countdownText = formatCountdown(timeRemaining)
        updateDisplay()
        
        // Also update the popover content if it's showing
        if let popover = popover, popover.isShown {
            updatePopoverContent()
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
        
        guard let nextPrayer = nextPrayer else {
            return "--:--"
        }
        
        switch format {
        case .countdown:
            return countdownText
            
        case .nextPrayerTime:
            return "\(nextPrayer.prayerType.displayName) \(nextPrayer.time.formattedTime)"
            
        case .nextPrayerName:
            return nextPrayer.prayerType.displayName
            
        case .iconAndCountdown:
            let icon = showIcon ? "\(getPrayerIconSymbol(for: nextPrayer.prayerType)) " : ""
            return "\(icon)\(countdownText)"
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
        updatePrayerData()
        NotificationCenter.default.post(name: .refreshPrayerTimes, object: nil)
    }
    
    @objc private func showPreferences() {
        // Show preferences window
        let preferencesView = PreferencesView()
        let hostingController = NSHostingController(rootView: preferencesView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.contentViewController = hostingController
        window.title = "Preferences"
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func hideStatusBarWidget() {
        preferencesManager.isStatusBarWidgetEnabled = false
    }
    
    // MARK: - Lifecycle
    
    deinit {
        timer?.invalidate()
        statusItem = nil
        popover = nil
        popoverContentController = nil
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let statusBarWidgetToggled = Notification.Name("StatusBarWidgetToggled")
}