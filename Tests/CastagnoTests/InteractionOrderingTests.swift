import XCTest
@testable import CastagnoCore
@testable import OpenCastSwift
import SwiftyJSON

final class InteractionOrderingTests: XCTestCase {
    private final class Clients { var values: [String: CastClient] = [:] }

    private func makeStore(hold: TimeInterval = 30) -> (DeviceStore, Clients) {
        let scanner = CastDeviceScanner()
        let clients = Clients()
        let store = DeviceStore(scanner: scanner, startScanning: false, interactionHoldInterval: hold,
            makeSession: { device in
                DeviceSession(device: device, startConnection: { clients.values[device.id] = $0 },
                              sendPlayback: { _, _ in })
            })
        for id in ["Alpha", "Zebra"] {
            scanner.addDevice(CastDevice(id: id, name: id, modelName: "Speaker", hostName: "test.local",
                ipAddress: "", port: 8009, capabilitiesMask: 4, status: "", iconPath: ""))
            let app = CastApp()
            app.sessionId = id
            app.transportId = id
            app.namespaces = [CastNamespace.media]
            let status = CastStatus()
            status.apps = [app]
            let session = store.session(id: id)!
            session.castClient(clients.values[id]!, deviceStatusDidChange: status)
            session.castClient(clients.values[id]!, mediaStatusDidChange: media(id == "Zebra" ? "PLAYING" : "PAUSED", id: id))
        }
        return (store, clients)
    }

    private func media(_ state: String, id: String) -> CastMediaStatus {
        CastMediaStatus(json: JSON(["playerState": state, "mediaSessionId": 1]), sourceId: id)
    }

    func testPausedDeviceStaysInItsRowAfterInteractionThenReturnsToNormalSorting() {
        let (store, clients) = makeStore(hold: 0.01)
        defer { store.shutdown() }
        XCTAssertEqual(store.devices.map(\.id), ["Zebra", "Alpha"])
        let zebra = store.session(id: "Zebra")!
        zebra.setPlaying(false)
        zebra.castClient(clients.values["Zebra"]!, mediaStatusDidChange: media("PAUSED", id: "Zebra"))
        XCTAssertEqual(store.devices.map(\.id), ["Zebra", "Alpha"])
        let expired = expectation(description: "Interaction hold expires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { expired.fulfill() }
        wait(for: [expired], timeout: 1)
        XCTAssertEqual(store.devices.map(\.id), ["Alpha", "Zebra"])
    }

    func testVolumeInteractionPreservesLowerRowInsteadOfMovingItToTop() {
        let (store, clients) = makeStore()
        defer { store.shutdown() }
        store.session(id: "Alpha")!.setVolume(0.3)
        store.session(id: "Zebra")!.castClient(clients.values["Zebra"]!,
            mediaStatusDidChange: media("PAUSED", id: "Zebra"))
        XCTAssertEqual(store.devices.map(\.id), ["Zebra", "Alpha"])
    }

    func testExternalPauseWithoutInteractionUsesPlayingFirstOrderingNormally() {
        let (store, clients) = makeStore()
        defer { store.shutdown() }
        store.session(id: "Zebra")!.castClient(clients.values["Zebra"]!,
            mediaStatusDidChange: media("PAUSED", id: "Zebra"))
        XCTAssertEqual(store.devices.map(\.id), ["Alpha", "Zebra"])
    }
}
