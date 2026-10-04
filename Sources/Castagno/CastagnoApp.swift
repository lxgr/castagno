import AppKit
import SwiftUI
import CastagnoCore

struct CastagnoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            DeviceListView(store: delegate.store)
        } label: {
            Image(nsImage: ChestnutIcon.menuBar)
                .accessibilityLabel("Castagno")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Own discovery for the app's lifetime, independently of the lazy popover.
    let store = CommandLine.arguments.dropFirst().elementsEqual(["--demo"]) ? DeviceStore.demo() : DeviceStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
