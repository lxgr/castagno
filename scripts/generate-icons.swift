import AppKit

@main
struct GenerateIcons {
    static var appIcon: NSImage!
    static var menuIcon: NSImage!

    static func drawAppIcon(in rect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        appIcon.draw(in: rect)
    }

    static func drawMenu(in rect: NSRect, ink: NSColor = .black) {
        let tinted = NSImage(size: rect.size, flipped: false) { local in
            menuIcon.draw(in: local)
            ink.setFill()
            local.fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: rect)
    }
    static func png(width: Int, height: Int, draw: (NSRect) -> Void) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
        let folder = root.appendingPathComponent("Resources/Icons")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        appIcon = NSImage(contentsOf: folder.appendingPathComponent("AppIcon.png"))!
        menuIcon = NSImage(contentsOf: folder.appendingPathComponent("MenuBar@2x.png"))!
        var icns = Data("icns".utf8)
        var entries = Data()
        for (size, type) in [(16, "icp4"), (32, "icp5"), (64, "icp6"), (128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10"), (32, "ic11"), (64, "ic12"), (256, "ic13"), (512, "ic14")] {
            let data = png(width: size, height: size, draw: drawAppIcon)
            entries.append(Data(type.utf8))
            var length = UInt32(data.count + 8).bigEndian
            withUnsafeBytes(of: &length) { entries.append(contentsOf: $0) }
            entries.append(data)
            if size == 1024 { try data.write(to: folder.appendingPathComponent("AppIcon.png")) }
        }
        var length = UInt32(entries.count + 8).bigEndian
        withUnsafeBytes(of: &length) { icns.append(contentsOf: $0) }
        icns.append(entries)
        try icns.write(to: folder.appendingPathComponent("AppIcon.icns"))
        let preview = png(width: 1200, height: 760) { rect in
            NSColor(srgbRed: 0.96, green: 0.94, blue: 0.90, alpha: 1).setFill()
            rect.fill()
            func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .labelColor) {
                (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
            }
            label("Castagno", x: 70, y: 660, size: 40, color: NSColor(srgbRed: 0.27, green: 0.17, blue: 0.11, alpha: 1))
            label("A little chestnut. A lot of sound.", x: 72, y: 624, size: 19, color: .darkGray)
            drawAppIcon(in: NSRect(x: 58, y: 150, width: 440, height: 440))
            label("APP ICON", x: 78, y: 105, size: 14, color: .darkGray)
            label("MENU BAR · ACTUAL SIZE", x: 620, y: 550, size: 14, color: .darkGray)
            for (y, dark) in [(CGFloat(478), false), (CGFloat(404), true)] {
                (dark ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1) : .white).setFill()
                NSBezierPath(roundedRect: NSRect(x: 610, y: y, width: 510, height: 46), xRadius: 10, yRadius: 10).fill()
                NSGraphicsContext.saveGraphicsState()
                let iconRect = NSRect(x: 648, y: y + 14, width: 18, height: 18)
                drawMenu(in: iconRect, ink: dark ? .white : .black)
                NSGraphicsContext.restoreGraphicsState()
                label("◖  Wi-Fi       Sun 4 Oct   11:42", x: 825, y: y + 14, size: 14, color: dark ? .white : .darkGray)
            }
            label("SAME SHAPE, EVERY SIZE", x: 620, y: 306, size: 14, color: .darkGray)
            for (x, size) in [(CGFloat(616), CGFloat(128)), (CGFloat(778), CGFloat(64)), (CGFloat(878), CGFloat(32)), (CGFloat(946), CGFloat(16))] {
                drawAppIcon(in: NSRect(x: x, y: 140, width: size, height: size))
            }
        }
        try preview.write(to: folder.appendingPathComponent("Preview.png"))
        print("Generated app icon, menu bar exports, and preview in \(folder.path)")
    }
}
