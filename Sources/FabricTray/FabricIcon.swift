import AppKit
import SwiftUI

enum FabricIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for type: FabricItemType) -> NSImage? {
        let name = type.svgIconName
        return loadSVG(named: name, size: 16)
    }

    static func trayIcon() -> NSImage? {
        return loadSVG(named: "fabric_tray", size: 18, isTemplate: true)
    }

    private static func loadSVG(named name: String, size: CGFloat, isTemplate: Bool = false) -> NSImage? {
        let cacheKey = "\(name)_\(size)_\(isTemplate)"
        if let cached = cache[cacheKey] { return cached }
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "svg", subdirectory: "Resources/Icons"
        ) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) else { return nil }
        img.size = NSSize(width: size, height: size)
        img.isTemplate = isTemplate
        cache[cacheKey] = img
        return img
    }
}

struct FabricIconView: View {
    let type: FabricItemType
    let size: CGFloat

    init(_ type: FabricItemType, size: CGFloat = 14) {
        self.type = type
        self.size = size
    }

    var body: some View {
        if let nsImage = FabricIcon.image(for: type) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: type.icon)
                .font(.system(size: size * 0.7))
                .frame(width: size, height: size)
        }
    }
}
