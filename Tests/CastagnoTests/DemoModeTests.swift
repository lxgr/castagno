import XCTest
@testable import CastagnoCore

final class DemoModeTests: XCTestCase {
    func testDemoSceneUsesOnlyFictionalReceiversAndShowsPlayingFirst() throws {
        let store = DeviceStore.demo()
        defer { store.shutdown() }
        XCTAssertTrue(store.isDemo)
        XCTAssertEqual(store.devices.map { $0.device.name }, ["Living Room", "Upstairs", "Kitchen"])
        let snapshots = store.snapshot().devices
        XCTAssertEqual(snapshots.map(\.kind), [.stereoPair, .speakerGroup, .device])
        XCTAssertEqual(snapshots.map(\.isGroup), [true, true, false])
        XCTAssertEqual(snapshots.map(\.isPlaying), [true, true, false])
        XCTAssertEqual(snapshots.map(\.title), ["Islands of Men", "sneakers4free", "Olson"])
        XCTAssertEqual(snapshots.map(\.detail), ["Geese · Spotify", "Bilderbuch · Spotify", "Boards of Canada · Spotify"])
        XCTAssertEqual(snapshots.last?.displayModel, "Google Nest Hub")
        XCTAssertFalse(store.discoveryProgress.isBusy)
        XCTAssertEqual(store.discoveryProgress.discoveredDevices, 3)
        XCTAssertEqual(store.snapshot(includeGroupMembers: true).devices.count, 3)
        for snapshot in snapshots {
            XCTAssertTrue(snapshot.id.hasPrefix("demo-"))
            XCTAssertEqual(snapshot.address, "")
            XCTAssertEqual(snapshot.host, "")
            XCTAssertEqual(snapshot.connectionAttempts, 0)
            XCTAssertTrue(snapshot.connected)
            XCTAssertTrue(snapshot.canControlPlayback)
        }
    }

    func testDemoControlsStayLocalAndRefreshRestoresScreenshotScene() throws {
        let store = DeviceStore.demo()
        defer { store.shutdown() }
        let initial = store.snapshot()
        let pair = try XCTUnwrap(store.session(id: "demo-living-room"))
        pair.setVolume(0.75)
        pair.setEditing(false)
        pair.toggleMute()
        XCTAssertEqual(pair.confirmedVolume, 0.75)
        XCTAssertTrue(pair.muted)
        XCTAssertTrue(pair.togglePlayback())
        XCTAssertFalse(pair.playback.isPlaying)
        XCTAssertEqual(store.devices.first?.id, pair.id, "Demo uses the same interaction hold as real devices")
        XCTAssertTrue(pair.togglePlayback())
        XCTAssertTrue(pair.playback.isPlaying)
        pair.connect()
        XCTAssertEqual(pair.connectionAttempts, 0)
        store.rescan()
        XCTAssertEqual(store.snapshot(), initial)
        XCTAssertFalse(pair.ready, "Reset stops the previous demo sessions")
        XCTAssertFalse(pair.setPlaying(true))
    }

    func testDemoSessionNeverStartsCastTransport() {
        let fixture = DemoReceiver.scene[0]
        let session = DeviceSession(device: fixture.device,
            startConnection: { _ in XCTFail("Demo must not start a Cast connection") }, demo: fixture)
        defer { session.stop() }
        session.connect()
        session.setVolume(0.3)
        session.setMuted(true)
        XCTAssertTrue(session.setPlaying(false))
        XCTAssertEqual(session.connectionAttempts, 0)
    }
}
