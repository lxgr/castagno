import XCTest
@testable import CastagnoCore
@testable import OpenCastSwift
import SwiftyJSON

final class PlaybackControlTests: XCTestCase {
    private func makeSession(state: String = "PLAYING", mediaID: Int = 1, timeout: TimeInterval = 5,
                             send: @escaping (Bool) -> Void = { _ in }) -> (DeviceSession, CastClient) {
        let device = CastDevice(id: "speaker", name: "Speaker", modelName: "Speaker", hostName: "test.local",
                                ipAddress: "", port: 8009, capabilitiesMask: 4, status: "", iconPath: "")
        var client: CastClient!
        let session = DeviceSession(device: device, startConnection: { client = $0 },
                                    sendPlayback: { _, playing in send(playing) }, playbackConfirmationTimeout: timeout)
        let app = CastApp()
        app.sessionId = "app"
        app.transportId = "transport"
        app.namespaces = [CastNamespace.media]
        let status = CastStatus()
        status.apps = [app]
        session.castClient(client, deviceStatusDidChange: status)
        session.castClient(client, mediaStatusDidChange: media(state, id: mediaID))
        return (session, client)
    }

    private func media(_ state: String, id: Int = 1, source: String = "transport") -> CastMediaStatus {
        CastMediaStatus(json: JSON(["playerState": state, "mediaSessionId": id]), sourceId: source)
    }

    func testPauseResumeWaitForReceiverAndRejectDuplicateOrStaleConfirmations() {
        var commands: [Bool] = []
        let (session, client) = makeSession(send: { commands.append($0) })
        defer { session.stop() }
        XCTAssertTrue(session.togglePlayback())
        XCTAssertTrue(session.playback.isPlaying) // No optimistic media state.
        XCTAssertTrue(session.playbackActionPending)
        XCTAssertFalse(session.togglePlayback())
        session.castClient(client, mediaStatusDidChange: media("PAUSED", source: "stale-app"))
        XCTAssertTrue(session.playbackActionPending)
        session.castClient(client, mediaStatusDidChange: media("PAUSED"))
        XCTAssertFalse(session.playbackActionPending)
        XCTAssertTrue(session.canControlPlayback)
        XCTAssertTrue(session.togglePlayback())
        session.castClient(client, mediaStatusDidChange: media("PLAYING"))
        XCTAssertEqual(commands, [false, true])
        XCTAssertFalse(session.playbackActionPending)
    }

    func testIdleAndMissingMediaSessionCannotStartPlayback() {
        for (state, id) in [("IDLE", 1), ("PLAYING", 0), ("BUFFERING", 1)] {
            let (session, _) = makeSession(state: state, mediaID: id, send: { _ in XCTFail("Must not send") })
            XCTAssertFalse(session.canControlPlayback)
            XCTAssertFalse(session.setPlaying(true))
            session.stop()
        }
    }

    func testChangedMediaSessionDoesNotConfirmTheOldCommand() {
        let (session, client) = makeSession()
        defer { session.stop() }
        session.setPlaying(false)
        session.castClient(client, mediaStatusDidChange: media("PAUSED", id: 2))
        XCTAssertFalse(session.playbackActionPending)
        XCTAssertNotNil(session.playbackControlError)
    }

    func testUnconfirmedControlTimesOutAndAllowsRetry() {
        let (session, _) = makeSession(timeout: 0.01)
        defer { session.stop() }
        session.setPlaying(false)
        let elapsed = expectation(description: "Confirmation timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 1)
        XCTAssertFalse(session.playbackActionPending)
        XCTAssertTrue(session.canControlPlayback)
        XCTAssertNotNil(session.playbackControlError)
    }

    func testStopCancelsThePlaybackConfirmationTimeout() {
        let (session, _) = makeSession(timeout: 0.01)
        session.setPlaying(false)
        session.stop()
        let elapsed = expectation(description: "No late timeout after stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 1)
        XCTAssertFalse(session.playbackActionPending)
        XCTAssertNil(session.playbackControlError)
        XCTAssertFalse(session.canControlPlayback)
    }
}
