//
//  PrayerProApp.swift
//  PrayerPro
//
//  Created by Ali Karadeniz on 24.07.25.
//

import SwiftUI

@main
struct PrayerProApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
