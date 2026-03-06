import AppKit
import SwiftUI

enum FabricIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for type: FabricItemType) -> NSImage? {
        let name = type.svgIconName
        return loadSVG(named: name, size: 16)
    }

    static func trayIcon() -> NSImage? {
        // Always use programmatic drawing for the menu bar icon.
        // SVGs with currentColor don't render reliably with NSImage(data:).
        return drawTrayDiamond(size: 18)
    }

    /// Draw a faceted diamond icon suitable for the macOS menu bar.
    /// Uses solid black on transparent — macOS template rendering handles light/dark.
    private static func drawTrayDiamond(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let cx = rect.midX, cy = rect.midY
            let r = min(rect.width, rect.height) * 0.44

            let top    = NSPoint(x: cx, y: cy + r)
            let bottom = NSPoint(x: cx, y: cy - r)
            let left   = NSPoint(x: cx - r * 0.82, y: cy + r * 0.05)
            let right  = NSPoint(x: cx + r * 0.82, y: cy + r * 0.05)

            // Crown inner points
            let itl = NSPoint(x: cx - r * 0.3, y: cy + r * 0.42)
            let itr = NSPoint(x: cx + r * 0.3, y: cy + r * 0.42)

            NSColor.black.setStroke()
            NSColor.black.withAlphaComponent(0.15).setFill()

            // Outer diamond
            let outline = NSBezierPath()
            outline.move(to: top)
            outline.line(to: left)
            outline.line(to: bottom)
            outline.line(to: right)
            outline.close()
            outline.lineWidth = 1.2
            outline.fill()
            outline.stroke()

            // Crown facet (filled darker)
            let crown = NSBezierPath()
            crown.move(to: top)
            crown.line(to: itl)
            crown.line(to: itr)
            crown.close()
            NSColor.black.withAlphaComponent(0.55).setFill()
            crown.fill()

            // Inner facet lines
            NSColor.black.withAlphaComponent(0.5).setStroke()
            let lines: [(NSPoint, NSPoint)] = [
                (itl, itr), (itl, left), (itr, right),
                (itl, bottom), (itr, bottom),
                (NSPoint(x: cx, y: cy + r * 0.42), bottom),
            ]
            for (a, b) in lines {
                let line = NSBezierPath()
                line.move(to: a)
                line.line(to: b)
                line.lineWidth = 0.7
                line.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
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
