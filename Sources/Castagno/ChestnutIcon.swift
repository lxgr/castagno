import AppKit

/// Native exports of the editable SVG artwork in Resources/Icons.
enum ChestnutIcon {
    private static let artworkBundle: Bundle = {
        if let url = Bundle.main.url(forResource: "Castagno_Castagno", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for name in ["MenuBar", "MenuBar@2x"] {
            guard let url = artworkBundle.url(forResource: name, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data) else {
                preconditionFailure("Missing bundled menu bar artwork: \(name)")
            }
            rep.size = image.size
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        image.accessibilityDescription = "Castagno chestnut speaker"
        return image
    }()

}
