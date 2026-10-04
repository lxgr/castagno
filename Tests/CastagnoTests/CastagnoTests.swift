import Foundation
import XCTest
@testable import CastagnoCore
@testable import CastagnoCLI
@testable import OpenCastSwift
import SwiftyJSON

final class CastagnoTests: XCTestCase {
    func testFramingAcceptsNetworkChunksWithoutInputStream() {
        let reader = CastV2PlatformReader()
        reader.append(Data([0, 0, 0, 2, 10]))
        XCTAssertNil(reader.nextMessage())
        reader.append(Data([20]))
        XCTAssertEqual(reader.nextMessage(), Data([10, 20]))
    }
    func testDiscoveryUpdatesChangedAddressAndPortForSameReceiver() {
        let scanner = CastDeviceScanner()
        let original = device("speaker")
        let moved = CastDevice(id: "speaker", name: "speaker", modelName: "Speaker",
                               hostName: "speaker.local", ipAddress: "192.168.1.3", port: 32100,
                               capabilitiesMask: 4, status: "", iconPath: "")
        scanner.addDevice(original)
        scanner.addDevice(moved)
        XCTAssertEqual(scanner.devices.count, 1)
        XCTAssertEqual(scanner.devices.first?.ipAddress, "192.168.1.3")
        XCTAssertEqual(scanner.devices.first?.port, 32100)
    }
    private func mediaApp() -> CastApp {
        let app = CastApp()
        app.displayName = "Spotify"
        app.statusText = "Casting music"
        app.sessionId = "app-session"
        app.transportId = "transport-1"
        app.namespaces = [CastNamespace.media]
        return app
    }

    func testPlayingMetadataAndPausedState() {
        let app = mediaApp()
        let status = CastMediaStatus(json: JSON([
            "playerState": "PLAYING", "mediaSessionId": 1,
            "media": ["metadata": ["title": "Song", "artist": "Artist"]]
        ]))
        let info = PlaybackInfo(app: app, media: status)
        XCTAssertTrue(info.isPlaying)
        XCTAssertEqual(info.title, "Song")
        XCTAssertEqual(info.detail, "Artist · Spotify")
        let paused = PlaybackInfo(app: app, media: CastMediaStatus(json: JSON(["playerState": "PAUSED"])))
        XCTAssertFalse(paused.isPlaying)
        XCTAssertEqual(paused.label, "Paused")
        XCTAssertEqual(paused.title, "Casting music")
    }

    func testIdleAndUnknownPlaybackDoNotPretendToBePlaying() {
        let app = mediaApp()
        XCTAssertFalse(PlaybackInfo(app: app).isPlaying)
        let idle = PlaybackInfo(app: app, media: CastMediaStatus(json: JSON(["playerState": "IDLE"])))
        XCTAssertNil(idle.title)
        XCTAssertFalse(idle.isPlaying)
        XCTAssertEqual(CastMediaStatus(json: JSON([:])).playerState, .idle)
        app.isIdleScreen = true
        XCTAssertNil(PlaybackInfo(app: app).title)
    }

    func testPlayingDevicesSortFirstWithStableAlphabeticalTies() {
        XCTAssertTrue(DeviceOrdering.precedes(playing: true, name: "Zebra", id: "z",
                                              otherPlaying: false, otherName: "Alpha", otherID: "a"))
        XCTAssertFalse(DeviceOrdering.precedes(playing: false, name: "Alpha", id: "a",
                                               otherPlaying: true, otherName: "Zebra", otherID: "z"))
        XCTAssertTrue(DeviceOrdering.precedes(playing: true, name: "Alpha", id: "a",
                                              otherPlaying: true, otherName: "Zebra", otherID: "z"))
        XCTAssertTrue(DeviceOrdering.precedes(playing: false, name: "Same", id: "a",
                                              otherPlaying: false, otherName: "Same", otherID: "b"))
    }

    func testPartialMediaUpdatesPreserveTitleAndEmptyStatusClearsIt() {
        let sink = RecordingSink()
        let channel = MediaControlChannel()
        channel.requestDispatcher = sink
        channel.observe(mediaApp())
        channel.handleResponse(JSON(["type": "MEDIA_STATUS", "status": [[
            "mediaSessionId": 1, "playerState": "PLAYING",
            "media": ["contentId": "track-1", "metadata": ["title": "Song"]]
        ]]]), sourceId: "transport-1")
        channel.handleResponse(JSON(["type": "MEDIA_STATUS", "status": [[
            "mediaSessionId": 1, "playerState": "PAUSED"
        ]]]), sourceId: "transport-1")
        XCTAssertEqual(sink.mediaStatuses.last?.metadata?["title"].string, "Song")
        XCTAssertEqual(sink.mediaStatuses.last?.playerState, .paused)
        channel.handleResponse(JSON(["type": "MEDIA_STATUS", "status": []]), sourceId: "transport-1")
        XCTAssertEqual(sink.mediaStatuses.last?.playerState, .idle)
        XCTAssertNil(sink.mediaStatuses.last?.metadata?["title"].string)
    }

    func testTrackAndAppChangesDiscardStaleMetadata() {
        let sink = RecordingSink()
        let channel = MediaControlChannel()
        channel.requestDispatcher = sink
        let app = mediaApp()
        channel.observe(app)
        channel.handleResponse(JSON(["type": "MEDIA_STATUS", "status": [[
            "mediaSessionId": 1, "playerState": "PLAYING",
            "media": ["contentId": "track-1", "metadata": ["title": "Old Song"]]
        ]]]), sourceId: "transport-1")
        channel.handleResponse(JSON(["type": "MEDIA_STATUS", "status": [[
            "mediaSessionId": 1, "playerState": "PLAYING", "media": ["contentId": "track-2"]
        ]]]), sourceId: "transport-1")
        XCTAssertNil(sink.mediaStatuses.last?.metadata?["title"].string)
        let newApp = mediaApp()
        newApp.transportId = "transport-2"
        newApp.sessionId = "new-session"
        channel.observe(newApp)
        let previousCount = sink.mediaStatuses.count
        channel.handleResponse(JSON(["type": "MEDIA_STATUS", "status": [["playerState": "PLAYING"]]]), sourceId: "transport-1")
        XCTAssertEqual(sink.mediaStatuses.count, previousCount)
        channel.handleResponse(JSON(["type": "MEDIA_STATUS", "status": [["mediaSessionId": 2, "playerState": "PAUSED"]]]), sourceId: "transport-2")
        XCTAssertNil(sink.mediaStatuses.last?.metadata?["title"].string)
    }
    private func device(_ id: String, group: Bool = false) -> CastDevice {
        CastDevice(id: id, name: id, modelName: group ? "Google Cast Group" : "Speaker",
                   hostName: "speaker.local", ipAddress: "192.168.1.2", port: 8009,
                   capabilitiesMask: group ? DeviceCapabilities.multizoneGroup.rawValue : 4,
                   status: "", iconPath: "")
    }

    func testGroupMembersAreHiddenButGroupsAndStandaloneSpeakersRemain() {
        let discovered = [device("group", group: true), device("AA-BB"), device("standalone")]
        XCTAssertEqual(GroupVisibility.visibleIDs(devices: discovered, membersByGroup: [:]),
                       Set(["group", "AA-BB", "standalone"]))
        // All records share a hostname: matching is by UUID, never by host or name.
        XCTAssertEqual(GroupVisibility.visibleIDs(devices: discovered,
                                                  membersByGroup: ["group": ["aabb", "", "group"]]),
                       Set(["group", "standalone"]))
    }

    func testGroupModelIsRecognizedWithoutMultizoneCapabilityBit() {
        let group = CastDevice(id: "group", name: "Everywhere", modelName: "Google Cast Group",
                               hostName: "speaker.local", ipAddress: "192.168.1.2", port: 32000,
                               capabilitiesMask: 4, status: "", iconPath: "")
        XCTAssertTrue(group.isGroup)
        XCTAssertFalse(device("speaker").isGroup)
        XCTAssertEqual(GroupVisibility.visibleIDs(devices: [group, device("speaker")],
                                                  membersByGroup: ["group": ["speaker"]]), ["group"])
    }

    func testMembersReturnWhenGroupDisappearsOrMembershipChanges() {
        let discovered = [device("group", group: true), device("speaker")]
        let membership: [String: Set<String>] = ["group": ["speaker"]]
        XCTAssertEqual(GroupVisibility.visibleIDs(devices: discovered, membersByGroup: membership), ["group"])
        XCTAssertEqual(GroupVisibility.visibleIDs(devices: [device("speaker")], membersByGroup: membership), ["speaker"])
        XCTAssertEqual(GroupVisibility.visibleIDs(devices: discovered, membersByGroup: ["group": []]),
                       Set(["group", "speaker"]))
    }

    func testOverlappingGroupsKeepSpeakerHiddenUntilItLeavesEveryGroup() {
        let discovered = [device("g1", group: true), device("g2", group: true), device("speaker")]
        XCTAssertEqual(GroupVisibility.visibleIDs(devices: discovered,
                                                  membersByGroup: ["g1": [], "g2": ["speaker"]]),
                       Set(["g1", "g2"]))
    }

    func testMultizoneSnapshotsAndLiveMembershipEventsReachClient() {
        let client = CastClient(device: device("group", group: true))
        let channel = MultizoneControlChannel()
        var snapshots: [[String]] = []
        client.multizoneStatusDidChange = { snapshots.append($0.devices.map(\.id)) }
        func member(_ id: String) -> CastMultizoneDevice {
            CastMultizoneDevice(name: id, volume: 0.5, isMuted: false, capabilitiesMask: 4, id: id)
        }
        client.channel(channel, didReceive: CastMultizoneStatus(devices: [member("a")]))
        client.channel(channel, added: member("b"))
        client.channel(channel, updated: member("b"))
        client.channel(channel, removed: "a")
        client.channel(channel, didReceive: CastMultizoneStatus(devices: []))
        XCTAssertEqual(snapshots, [["a"], ["a", "b"], ["a", "b"], ["b"], []])
    }

    func testVolumeBoundsAndInvalidInput() {
        XCTAssertEqual(VolumeValue.clamp(-0.2), 0)
        XCTAssertEqual(VolumeValue.clamp(1.4), 1)
        XCTAssertEqual(VolumeValue.clamp(.nan), 0)
        XCTAssertEqual(VolumeValue.clamp(.infinity), 0)
        XCTAssertEqual(VolumeValue.percent(0.456), 46)
    }

    func testFragmentedFramesAndUnalignedSecondHeader() {
        let reader = CastV2PlatformReader(stream: InputStream(data: Data()))
        reader.buffer.append(contentsOf: [0, 0])
        XCTAssertNil(reader.nextMessage())
        reader.buffer.append(contentsOf: [0, 3, 10])
        XCTAssertNil(reader.nextMessage())
        reader.buffer.append(contentsOf: [20, 30, 0, 0, 0, 1, 99])
        XCTAssertEqual(reader.nextMessage(), Data([10, 20, 30]))
        XCTAssertEqual(reader.nextMessage(), Data([99]))
        XCTAssertNil(reader.nextMessage())
    }

    func testReaderCompactsLargeFramesWithoutLosingNextPacket() {
        let reader = CastV2PlatformReader(stream: InputStream(data: Data()))
        let body = Data(repeating: 42, count: 8192)
        reader.buffer.append(contentsOf: [0, 0, 32, 0])
        reader.buffer.append(body)
        reader.buffer.append(contentsOf: [0, 0, 0, 1, 7])
        XCTAssertEqual(reader.nextMessage(), body)
        XCTAssertEqual(reader.nextMessage(), Data([7]))
        XCTAssertEqual(reader.readPosition, 5)
    }

    func testReaderRejectsOversizedFrames() {
        let reader = CastV2PlatformReader(stream: InputStream(data: Data()))
        reader.buffer.append(contentsOf: [127, 255, 255, 255])
        XCTAssertNil(reader.nextMessage())
        XCTAssertTrue(reader.buffer.isEmpty)
    }

    func testVolumeAndMuteTargetReceiverWithoutLaunchingAnApp() {
        let sink = RecordingSink()
        let channel = ReceiverControlChannel()
        channel.requestDispatcher = sink
        channel.setVolume(0.35)
        channel.setMuted(true)
        XCTAssertEqual(sink.requests.count, 3) // Initial GET_STATUS, volume, mute.
        let volume = sink.requests[1]
        XCTAssertEqual(volume.namespace, CastNamespace.receiver)
        XCTAssertEqual(volume.destinationId, CastConstants.receiver)
        if case .json(let payload) = volume.payload {
            let json = JSON(payload)
            XCTAssertEqual(json["type"].string, "SET_VOLUME")
            XCTAssertEqual(json["volume"]["level"].double ?? -1, 0.35, accuracy: 0.0001)
        } else { XCTFail("Expected JSON volume command") }
        if case .json(let payload) = sink.requests[2].payload {
            let json = JSON(payload)
            XCTAssertEqual(json["volume"]["muted"].bool, true)
        } else { XCTFail("Expected JSON mute command") }
    }

    func testPauseAndResumeTargetTheExistingMediaSessionWithoutLoadingAnything() {
        let sink = RecordingSink()
        let channel = MediaControlChannel()
        channel.requestDispatcher = sink
        channel.sendPause(for: mediaApp(), mediaSessionId: 42)
        channel.sendPlay(for: mediaApp(), mediaSessionId: 42)
        XCTAssertEqual(sink.requests.count, 2)
        for (request, type) in zip(sink.requests, ["PAUSE", "PLAY"]) {
            XCTAssertEqual(request.namespace, CastNamespace.media)
            XCTAssertEqual(request.destinationId, "transport-1")
            guard case .json(let payload) = request.payload else { return XCTFail("Expected JSON") }
            XCTAssertEqual(JSON(payload)["type"].string, type)
            XCTAssertEqual(JSON(payload)["mediaSessionId"].int, 42)
        }
    }
}

private final class RecordingSink: RequestDispatchable, MediaControlChannelDelegate {
    var requests: [CastRequest] = []
    var mediaStatuses: [CastMediaStatus] = []
    private var requestId = 0
    func nextRequestId() -> Int { requestId += 1; return requestId }
    func send(_ request: CastRequest, response: CastResponseHandler?) { requests.append(request) }
    func channel(_ channel: MediaControlChannel, didReceive mediaStatus: CastMediaStatus) {
        mediaStatuses.append(mediaStatus)
    }
}
