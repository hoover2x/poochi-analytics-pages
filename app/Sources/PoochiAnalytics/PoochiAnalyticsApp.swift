import SwiftUI

@main
@MainActor
struct PoochiAnalyticsApp: App {
    @StateObject private var store = AnalyticsStore()
    var body: some Scene {
        WindowGroup("Poochi Analytics") {
            ContentView().environmentObject(store)
                .frame(minWidth: 1000, minHeight: 680)
                .tint(PoochiStyle.teal)
        }
        .defaultSize(width: 1180, height: 800)
        Settings { SettingsView().environmentObject(store) }
    }
}
