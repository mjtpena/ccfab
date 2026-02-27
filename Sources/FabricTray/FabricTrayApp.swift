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
            trayIcon
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var trayIcon: some View {
        ZStack(alignment: .topTrailing) {
            if let icon = FabricIcon.trayIcon() {
                Image(nsImage: icon)
            } else {
                Image(systemName: appState.trayStatus.icon)
            }
            if appState.trayStatus.badgeCount > 0 {
                Text("\(appState.trayStatus.badgeCount)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(1)
                    .background(Circle().fill(.blue))
                    .offset(x: 4, y: -4)
            }
            if case .attention = appState.trayStatus {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                    .offset(x: 4, y: -4)
            }
        }
    }
}
