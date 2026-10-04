import XCTest
@testable import CastagnoCore
@testable import OpenCastSwift

final class DiscoveryTests: XCTestCase {
    private func store(scanner: CastDeviceScanner = CastDeviceScanner()) -> DeviceStore {
        DeviceStore(scanner: scanner, startScanning: false, settleInterval: 0.01,
                    makeSession: { DeviceSession(device: $0, startConnection: { _ in }) })
    }

    private func progress(pending: Int, devices: Int = 0, failed: Int = 0) -> CastDiscoveryProgress {
        CastDiscoveryProgress(isScanning: true, foundServices: pending + devices + failed,
                              resolvingServices: pending, failedServices: failed, discoveredDevices: devices)
    }

    private func device(_ id: String) -> CastDevice {
        CastDevice(id: id, name: id, modelName: "Speaker", hostName: "test.local", ipAddress: "",
                   port: 8009, capabilitiesMask: 4, status: "", iconPath: "")
    }

    func testDevicesAppearIncrementallyBeforeDiscoverySettles() {
        let scanner = CastDeviceScanner()
        let store = store(scanner: scanner)
        defer { store.shutdown() }
        scanner.addDevice(device("one"))
        XCTAssertEqual(store.devices.map(\.id), ["one"])
        store.receiveDiscoveryProgress(progress(pending: 1, devices: 1))
        XCTAssertTrue(store.discoveryProgress.isBusy)
        XCTAssertEqual(store.snapshot().discovery.resolvingServices, 1)
        scanner.addDevice(device("two"))
        XCTAssertEqual(Set(store.devices.map(\.id)), ["one", "two"])
        XCTAssertEqual(store.snapshot().discovery.discoveredDevices, 2)
    }

    func testQuietDiscoverySettlesAndPreservesUnresolvedCount() {
        let store = store()
        defer { store.shutdown() }
        store.receiveDiscoveryProgress(progress(pending: 0, devices: 2, failed: 1))
        let settled = expectation(description: "Initial scan settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(store.discoveryProgress.phase, .monitoring)
        XCTAssertFalse(store.discoveryProgress.isBusy)
        XCTAssertEqual(store.discoveryProgress.failedServices, 1)
        XCTAssertEqual(store.discoveryProgress.discoveredDevices, 2)
    }

    func testPendingResolutionCancelsCompletionAndShutdownCancelsTimers() {
        let store = store()
        store.receiveDiscoveryProgress(progress(pending: 0))
        store.receiveDiscoveryProgress(progress(pending: 1))
        let waited = expectation(description: "Old completion cannot override resolving")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { waited.fulfill() }
        wait(for: [waited], timeout: 1)
        XCTAssertEqual(store.discoveryProgress.phase, .resolving)
        store.receiveDiscoveryProgress(progress(pending: 0))
        store.shutdown()
        let stopped = expectation(description: "No completion after stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { stopped.fulfill() }
        wait(for: [stopped], timeout: 1)
        XCTAssertEqual(store.discoveryProgress.phase, .stopped)
    }

    func testScannerPublishesDeviceCountsAndIgnoresStaleBrowserCallbacks() {
        let scanner = CastDeviceScanner()
        var counts: [Int] = []
        scanner.progressDidChange = { counts.append($0.discoveredDevices) }
        scanner.addDevice(device("one"))
        scanner.addDevice(device("two"))
        scanner.reset()
        XCTAssertEqual(counts.prefix(2), [1, 2])
        XCTAssertEqual(counts.last, 0)
        scanner.netServiceBrowserWillSearch(NetServiceBrowser())
        XCTAssertFalse(scanner.isScanning)
    }
}
