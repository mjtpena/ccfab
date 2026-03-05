import SwiftUI
import Combine

enum TrayDensity: String, CaseIterable, Identifiable {
    case compact = "S"
    case standard = "M"
    case comfortable = "L"

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .compact: return 0.85
        case .standard: return 1.0
        case .comfortable: return 1.2
        }
    }

    var windowWidth: CGFloat { floor(360 * scale) }
    var minListHeight: CGFloat { floor(120 * scale) }
    var maxListHeight: CGFloat { floor(400 * scale) }
    var iconSize: CGFloat { floor(14 * scale) }
    var rowVPad: CGFloat { max(2, floor(4 * scale)) }
    var captionSize: CGFloat { floor(12 * scale) }
    var smallSize: CGFloat { max(9, floor(9 * scale)) }
    var tinySize: CGFloat { max(9, floor(9 * scale)) }
    var sfSize: CGFloat { floor(9 * scale) }
}

final class TrayPreferences: ObservableObject {
    @Published var density: TrayDensity
    private var cancellable: AnyCancellable?

    init() {
        let raw = UserDefaults.standard.string(forKey: "trayDensity") ?? "M"
        density = TrayDensity(rawValue: raw) ?? .standard
        cancellable = $density.dropFirst().sink { newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "trayDensity")
        }
    }
}
