import XCTest
@testable import CastagnoCore
@testable import OpenCastSwift

final class GroupMembershipTests: XCTestCase {
    private func device(_ id: String, group: Bool = false) -> CastDevice {
        CastDevice(id: id, name: id, modelName: group ? "Google Cast Group" : "Speaker",
                   hostName: "test.local", ipAddress: "", port: group ? 32000 : 8009,
                   capabilitiesMask: group ? 32 : 4, status: "", iconPath: "")
    }

    func testStereoPairMembersAreHiddenWhenCastStatusOnlyReportsThePairItself() {
        let devices = [device("AA-BB", group: true), device("left"), device("right"), device("standalone")]
        let memberships = GroupVisibility.memberships(devices: devices,
            reportedMembers: ["AA-BB": ["aabb"]],
            groupsByDevice: ["left": ["AABB"], "right": ["aa-bb"]])
        XCTAssertEqual(memberships["AA-BB"], ["left", "right"])
        XCTAssertEqual(GroupVisibility.visibleIDs(devices: devices, membersByGroup: memberships),
                       ["AA-BB", "standalone"])
    }

    func testSetupMembershipChangesAndMissingGroupsRestoreIndividualReceivers() {
        let devices = [device("group", group: true), device("left"), device("right")]
        let memberships = GroupVisibility.memberships(devices: devices, reportedMembers: [:],
            groupsByDevice: ["left": [], "right": ["missing-group"]])
        XCTAssertEqual(GroupVisibility.visibleIDs(devices: devices, membersByGroup: memberships),
                       ["group", "left", "right"])
    }

    func testSetupStatusParsesStaticAndDynamicMembershipWithoutNamesOrEmptyIDs() throws {
        let data = Data(#"{"multizone":{"groups":[{"uuid":"AA-BB","name":"Living"}],"dynamic_groups":[{"uuid":"cc-dd"},{"uuid":""}]}}"#.utf8)
        XCTAssertEqual(try GroupMembershipProbe.groupIDs(from: data), ["aabb", "ccdd"])
        XCTAssertEqual(try GroupMembershipProbe.groupIDs(from: Data(#"{"multizone":{"groups":[]}}"#.utf8)), [])
        XCTAssertThrowsError(try GroupMembershipProbe.groupIDs(from: Data("broken".utf8)))
    }

    func testStereoClassificationRequiresExplicitMultichannelAndLeftRightMetadata() throws {
        let data = Data(#"{"multizone":{"groups":[{"uuid":"AA-BB","multichannel_group":true,"channel_selection":"left"},{"uuid":"regular","multichannel_group":false,"channel_selection":"right"},{"uuid":"unknown","multichannel_group":true},{"uuid":"other-channel","multichannel_group":true,"channel_selection":"center"}],"dynamic_groups":[{"uuid":"CC-DD","multichannel_group":true,"channel_selection":"RIGHT"}]}}"#.utf8)
        let membership = try GroupMembershipProbe.membership(from: data)
        XCTAssertEqual(membership.groupIDs, ["aabb", "regular", "unknown", "otherchannel", "ccdd"])
        XCTAssertEqual(membership.stereoPairIDs, ["aabb", "ccdd"])
    }

    func testPairKindAndPhysicalModelReachSnapshotsAndCanChangeBackToAGroup() {
        let scanner = CastDeviceScanner()
        let store = DeviceStore(scanner: scanner, startScanning: false,
            makeSession: { DeviceSession(device: $0, startConnection: { _ in }) })
        defer { store.shutdown() }
        for item in [device("AA-BB", group: true), device("left"), device("right")] { scanner.addDevice(item) }
        XCTAssertEqual(store.session(id: "AA-BB")?.kind, .speakerGroup)
        for id in ["left", "right"] {
            store.session(id: id)?.updateMembership(ReceiverGroupMembership(groupIDs: ["aabb"], stereoPairIDs: ["aabb"]))
        }
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.devices.first?.kind, .stereoPair)
        XCTAssertEqual(store.devices.first?.displayModel, "Speaker · Stereo pair")
        XCTAssertEqual(store.snapshot().devices.first?.kind, .stereoPair)
        XCTAssertEqual(store.snapshot().devices.first?.memberIDs, ["left", "right"])
        for id in ["left", "right"] {
            store.session(id: id)?.updateMembership(ReceiverGroupMembership(groupIDs: ["aabb"]))
        }
        XCTAssertEqual(store.devices.first?.kind, .speakerGroup)
        XCTAssertEqual(store.devices.first?.displayModel, "Speaker group")
        XCTAssertTrue(store.devices.first?.device.isGroup == true) // Protocol identity is preserved.
    }

    func testTwoMatchingSpeakersDoNotMakeAnOrdinaryGroupAPair() {
        let scanner = CastDeviceScanner()
        let store = DeviceStore(scanner: scanner, startScanning: false,
            makeSession: { DeviceSession(device: $0, startConnection: { _ in }) })
        defer { store.shutdown() }
        for item in [device("group", group: true), device("left"), device("right")] { scanner.addDevice(item) }
        for id in ["left", "right"] {
            store.session(id: id)?.updateMembership(ReceiverGroupMembership(groupIDs: ["group"]))
        }
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.devices.first?.kind, .speakerGroup)
        XCTAssertEqual(store.session(id: "left")?.kind, .device)
    }
}
