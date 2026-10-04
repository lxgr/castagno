import AppKit
import SwiftUI
import XCTest
@testable import Castagno
@testable import CastagnoCore
@testable import OpenCastSwift

final class PopoverLayoutTests: XCTestCase {
    func testAboutIncludesProjectLicenseAndAllThirdPartyNotices() {
        XCTAssertTrue(AppLicenses.project.contains("Copyright (c) 2026 Lukas Ribisch"))
        XCTAssertTrue(AppLicenses.project.contains("MIT License"))
        for component in ["OpenCastSwift", "SwiftyJSON", "SwiftProtobuf", "Chromium Cast protocol", "Google Protocol Buffers"] {
            XCTAssertTrue(AppLicenses.thirdParty.contains(component), "Missing notice for \(component)")
        }
        XCTAssertTrue(AppLicenses.thirdParty.contains("Runtime Library Exception"))
        XCTAssertTrue(AppLicenses.thirdParty.contains("Copyright (c) 2013 The Chromium Authors"))
        XCTAssertTrue(AppLicenses.thirdParty.contains("Copyright 2008 Google Inc."))
    }

    private func makeStore() -> (DeviceStore, CastDeviceScanner) {
        let scanner = CastDeviceScanner()
        return (DeviceStore(scanner: scanner, startScanning: false,
            makeSession: { DeviceSession(device: $0, startConnection: { _ in }) }), scanner)
    }

    private func device(_ id: String) -> CastDevice {
        CastDevice(id: id, name: id, modelName: "Speaker", hostName: "test.local", ipAddress: "",
                   port: 8009, capabilitiesMask: 4, status: "", iconPath: "")
    }

    func testFirstOpeningWithAlreadyDiscoveredDevicesCannotCollapseToFooter() {
        let (store, scanner) = makeStore()
        defer { store.shutdown() }
        scanner.addDevice(device("one"))
        scanner.addDevice(device("two"))
        let view = NSHostingController(rootView: DeviceListView(store: store))
        // A menu bar window can ask for the minimum height on first opening.
        let size = view.sizeThatFits(in: CGSize(width: 380, height: 0))
        XCTAssertEqual(size.width, 380, accuracy: 1)
        XCTAssertGreaterThan(size.height, 240, "Both device rows must have an area before any refresh")
    }

    func testEmptyPopoverHasRoomForScanningInstructions() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        let view = NSHostingController(rootView: DeviceListView(store: store))
        let size = view.sizeThatFits(in: CGSize(width: 380, height: 0))
        XCTAssertGreaterThanOrEqual(size.height, 240)
        XCTAssertEqual(size.width, 380, accuracy: 1)
    }
}
