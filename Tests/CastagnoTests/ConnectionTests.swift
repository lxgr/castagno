import Foundation
import XCTest
@testable import CastagnoCore
@testable import OpenCastSwift

final class ConnectionTests: XCTestCase {
    private func device() -> CastDevice {
        CastDevice(id: "test", name: "Test", modelName: "Speaker", hostName: "test.local",
                   ipAddress: "", port: 8009, capabilitiesMask: 4, status: "", iconPath: "")
    }

    func testFailureReconnectsWithoutRefreshAndBackoffResetsAfterStatus() {
        var clients: [CastClient] = []
        var failures: [Int] = []
        let retried = expectation(description: "Automatically reconnected")
        let session = DeviceSession(device: device(), startConnection: {
            clients.append($0)
            if clients.count == 2 { retried.fulfill() }
        }, retryDelay: { failures.append($0); return 0.01 })
        defer { session.stop() }
        session.castClient(clients[0], connectionTo: device(), didFailWith: nil)
        XCTAssertTrue(session.failed)
        wait(for: [retried], timeout: 1)
        XCTAssertFalse(session.failed)
        XCTAssertEqual(session.connectionAttempts, 2)
        XCTAssertNotNil(session.lastConnectionError)
        session.castClient(clients[1], deviceStatusDidChange: CastStatus())
        XCTAssertTrue(session.ready)
        session.castClient(clients[1], didDisconnectFrom: device())
        XCTAssertEqual(failures, [1, 1])
    }

    func testStopCancelsPendingReconnect() {
        var clients: [CastClient] = []
        let unexpected = expectation(description: "No reconnect after shutdown")
        unexpected.isInverted = true
        let session = DeviceSession(device: device(), startConnection: {
            clients.append($0)
            if clients.count > 1 { unexpected.fulfill() }
        }, retryDelay: { _ in 0.01 })
        session.castClient(clients[0], connectionTo: device(), didFailWith: nil)
        session.stop()
        wait(for: [unexpected], timeout: 0.05)
        XCTAssertEqual(clients.count, 1)
    }

    func testManualRetryCancelsScheduledRetryAndIgnoresOldClient() {
        var clients: [CastClient] = []
        let unexpected = expectation(description: "No duplicate retry")
        unexpected.isInverted = true
        let session = DeviceSession(device: device(), startConnection: {
            clients.append($0)
            if clients.count > 2 { unexpected.fulfill() }
        }, retryDelay: { _ in 0.01 })
        defer { session.stop() }
        session.castClient(clients[0], connectionTo: device(), didFailWith: nil)
        session.connect()
        session.castClient(clients[0], deviceStatusDidChange: CastStatus())
        XCTAssertFalse(session.ready)
        session.castClient(clients[1], deviceStatusDidChange: CastStatus())
        wait(for: [unexpected], timeout: 0.05)
        XCTAssertTrue(session.ready)
        XCTAssertEqual(clients.count, 2)
    }
}
