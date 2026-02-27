import SwiftUI

@main
struct FabricTrayApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var prefs = TrayPreferences()

    var body: some Scene {
        MenuBarExtra {
            TrayView()
                .environmentObject(appState)
                .environmentObject(prefs)
        } label: {
            if let icon = FabricIcon.trayIcon() {
                Image(nsImage: icon)
            } else {
                Image(systemName: "diamond.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
