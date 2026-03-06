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

    // MARK: - Layout
    var windowWidth: CGFloat { floor(360 * scale) }
    var minListHeight: CGFloat { floor(120 * scale) }
    var maxListHeight: CGFloat { floor(400 * scale) }

    // MARK: - Icon sizes
    var iconSize: CGFloat { floor(14 * scale) }          // standard row icon
    var iconSmall: CGFloat { floor(10 * scale) }          // small inline icon
    var iconTiny: CGFloat { floor(8 * scale) }            // tiny indicator icon
    var iconMicro: CGFloat { floor(7 * scale) }           // chevron, badge
    var iconLarge: CGFloat { floor(16 * scale) }          // section header icon
    var iconHero: CGFloat { floor(20 * scale) }           // empty state icon

    // MARK: - Font sizes
    var fontHero: CGFloat { floor(16 * scale) }           // hero / empty-state title
    var fontTitle: CGFloat { floor(12 * scale) }          // toolbar icons, capacity name
    var fontHeading: CGFloat { floor(11 * scale) }        // section headings
    var fontBody: CGFloat { floor(10 * scale) }           // navigation text, row labels
    var fontCaption: CGFloat { max(9, floor(9 * scale)) } // captions, metadata
    var fontMicro: CGFloat { max(8, floor(8 * scale)) }   // tiny labels, badges
    var fontNano: CGFloat { max(7, floor(7 * scale)) }    // chevrons, super-small

    // Legacy aliases
    var captionSize: CGFloat { fontTitle }
    var smallSize: CGFloat { fontCaption }
    var tinySize: CGFloat { fontCaption }
    var sfSize: CGFloat { fontCaption }

    // MARK: - Padding
    var padXL: CGFloat { floor(24 * scale) }              // large empty state
    var padLG: CGFloat { floor(16 * scale) }              // section spacing
    var padMD: CGFloat { floor(10 * scale) }              // standard horizontal
    var padSM: CGFloat { floor(6 * scale) }               // small inner padding
    var padXS: CGFloat { max(3, floor(4 * scale)) }       // tight padding
    var padMicro: CGFloat { max(2, floor(2 * scale)) }    // minimal padding

    // MARK: - Spacing
    var spacingLG: CGFloat { floor(8 * scale) }
    var spacingSM: CGFloat { floor(4 * scale) }
    var spacingXS: CGFloat { floor(3 * scale) }

    // MARK: - Row
    var rowVPad: CGFloat { max(2, floor(4 * scale)) }
    var rowHPad: CGFloat { floor(12 * scale) }

    // MARK: - Misc
    var breadcrumbMaxW: CGFloat { floor(90 * scale) }
    var searchFieldVPad: CGFloat { max(3, floor(3 * scale)) }
    var badgePadH: CGFloat { max(4, floor(5 * scale)) }
    var badgePadV: CGFloat { max(1, floor(1 * scale)) }
    var progressSize: CGFloat { floor(14 * scale) }
    var skeletonTextW: ClosedRange<CGFloat> { floor(80*scale)...floor(160*scale) }
    var skeletonBarW: CGFloat { floor(40 * scale) }
    var skeletonBarH: CGFloat { floor(8 * scale) }
    var skeletonTextH: CGFloat { floor(10 * scale) }
}

final class TrayPreferences: ObservableObject {
    @Published var density: TrayDensity
    /// User-defined ordering of capacity IDs. Empty = default (active first, alphabetical).
    @Published var capacityOrder: [String] = []
    /// User-defined ordering of workspace IDs within each capacity. Key = capacityID, Value = ordered workspace IDs.
    @Published var workspaceOrder: [String: [String]] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        let raw = UserDefaults.standard.string(forKey: "trayDensity") ?? "M"
        density = TrayDensity(rawValue: raw) ?? .standard
        capacityOrder = UserDefaults.standard.stringArray(forKey: "capacityOrder") ?? []
        if let data = UserDefaults.standard.data(forKey: "workspaceOrder"),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            workspaceOrder = decoded
        }

        $density.dropFirst().sink { newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "trayDensity")
        }.store(in: &cancellables)

        $capacityOrder.dropFirst().sink { newValue in
            UserDefaults.standard.set(newValue, forKey: "capacityOrder")
        }.store(in: &cancellables)

        $workspaceOrder.dropFirst().sink { newValue in
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "workspaceOrder")
            }
        }.store(in: &cancellables)
    }
}
