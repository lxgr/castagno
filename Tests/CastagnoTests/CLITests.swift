import XCTest
@testable import CastagnoCLI
@testable import CastagnoCore

final class CLITests: XCTestCase {
    func testInvalidCommandDoesNotOverwriteOutputFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("keep".utf8).write(to: url)
        XCTAssertEqual(CastagnoCommandLine.run(["volume", "speaker", "nan", "--output", url.path]), 1)
        XCTAssertEqual(try String(contentsOf: url), "keep")
    }
    func testDiscoveryAndWatchOptions() throws {
        XCTAssertEqual(try Command.parse(["list"]), .list(all: false, timeout: 6))
        XCTAssertEqual(try Command.parse(["status", "--all", "--timeout", "2"]), .list(all: true, timeout: 2))
        XCTAssertEqual(try Command.parse(["watch"]), .watch(all: false, timeout: nil))
        XCTAssertEqual(try Command.parse(["watch", "--timeout", "1", "--all"]), .watch(all: true, timeout: 1))
    }

    func testControlCommands() throws {
        XCTAssertEqual(try Command.parse(["volume", "speaker-id", "35.5"]),
                       .volume(id: "speaker-id", percent: 35.5, timeout: 12))
        XCTAssertEqual(try Command.parse(["mute", "speaker-id", "toggle", "--timeout", "5"]),
                       .mute(id: "speaker-id", mode: .toggle, timeout: 5))
        XCTAssertEqual(try Command.parse(["pause", "speaker-id"]), .playback(id: "speaker-id", playing: false, timeout: 12))
        XCTAssertEqual(try Command.parse(["resume", "speaker-id"]), .playback(id: "speaker-id", playing: true, timeout: 12))
        XCTAssertEqual(try Command.parse(["play", "speaker-id"]), .playback(id: "speaker-id", playing: true, timeout: 12))
        XCTAssertEqual(try Command.parse(["toggle", "speaker-id"]), .playback(id: "speaker-id", playing: nil, timeout: 12))
        XCTAssertThrowsError(try Command.parse(["pause"]))
        XCTAssertThrowsError(try Command.parse(["resume", "speaker-id", "--all"]))
    }

    func testRejectsInvalidVolumeAndTimeoutBeforeDiscoveryStarts() {
        for value in ["-1", "101", "nan", "inf", "loud"] {
            XCTAssertThrowsError(try Command.parse(["volume", "speaker", value]))
        }
        for value in ["0", "-1", "61", "nan", "inf"] {
            XCTAssertThrowsError(try Command.parse(["list", "--timeout", value]))
        }
        XCTAssertThrowsError(try Command.parse(["list", "--timeout"]))
    }

    func testRejectsAmbiguousOrUnsupportedCommands() {
        XCTAssertThrowsError(try Command.parse(["volume", "speaker"]))
        XCTAssertThrowsError(try Command.parse(["mute", "speaker", "yes"]))
        XCTAssertThrowsError(try Command.parse(["list", "speaker"]))
        XCTAssertThrowsError(try Command.parse(["list", "--unknown"]))
        XCTAssertThrowsError(try Command.parse(["volume", "speaker", "50", "--all"]))
        XCTAssertThrowsError(try Command.parse(["launch", "spotify"]))
    }

    func testSnapshotRoundTripsWithoutExposingTransportObjects() throws {
        let device = DeviceSnapshot(id: "group", name: "Everywhere", model: "Google Cast Group",
                                    host: "speaker.local", address: "192.168.1.2", port: 32000,
                                    isGroup: true, kind: .speakerGroup, displayModel: "Speaker group",
                                    memberIDs: ["speaker"], connected: true,
                                    failed: false, connectionStatus: "Connected", volumePercent: 35,
                                    muted: false, isPlaying: true, playbackState: "PLAYING",
                                    title: "Song", detail: "Artist · Spotify",
                                    connectionAttempts: 1, lastConnectionError: nil,
                                    canControlPlayback: true, playbackActionPending: false, playbackControlError: nil)
        let snapshot = DiscoverySnapshot(devices: [device], discoveryError: nil)
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(DiscoverySnapshot.self, from: data), snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let devices = try XCTUnwrap(object["devices"] as? [[String: Any]])
        XCTAssertEqual(devices[0]["title"] as? String, "Song")
        XCTAssertEqual(devices[0]["volumePercent"] as? Double, 35)
    }
}
