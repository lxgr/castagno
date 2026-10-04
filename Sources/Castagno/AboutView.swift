import AppKit
import SwiftUI

enum AppLicenses {
    static func text(named name: String, extension suffix: String? = nil) -> String {
        let packagedBundle = Bundle.main.url(forResource: "Castagno_Castagno", withExtension: "bundle")
            .flatMap { Bundle(url: $0) }
        let bundle = packagedBundle ?? Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: suffix),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("Missing bundled license: \(name)")
        }
        return text
    }

    static let project = text(named: "LICENSE")
    static let thirdParty = text(named: "THIRD-PARTY-NOTICES", extension: "txt")
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Castagno").font(.title.bold())
                    Text("Sound around you").foregroundStyle(.secondary)
                    Text("A tiny Google Cast volume controller").font(.callout)
                }
                Spacer()
            }
            Text("Castagno is licensed under MIT. Third-party components are licensed as outlined below.")
                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Castagno — MIT").font(.headline)
                    Text(AppLicenses.project)
                    Text(AppLicenses.thirdParty)
                }
                .font(.system(size: 12)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(24).frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 600)
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "About Castagno"
        window.contentViewController = NSHostingController(rootView: AboutView())
        window.minSize = NSSize(width: 480, height: 440)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("Use the shared About window") }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
