import OpenCastSwift

/// Entirely fictional receivers: no addresses, discovery, or Cast connections.
struct DemoReceiver {
    let id: String
    let name: String
    let model: String
    let kind: ReceiverKind
    let title: String
    let artist: String
    let playing: Bool
    let volume: Double

    var device: CastDevice {
        CastDevice(id: id, name: name, modelName: kind == .device ? model : "Google Cast Group",
                   hostName: "", ipAddress: "", port: kind == .device ? 8009 : 32000,
                   capabilitiesMask: kind == .device ? 4 : 32, status: "", iconPath: "")
    }

    static let scene: [DemoReceiver] = [
        DemoReceiver(id: "demo-living-room", name: "Living Room", model: "Nest Audio · Stereo pair",
                     kind: .stereoPair, title: "Islands of Men", artist: "Geese", playing: true, volume: 0.42),
        DemoReceiver(id: "demo-kitchen", name: "Kitchen", model: "Google Nest Hub",
                     kind: .device, title: "Olson", artist: "Boards of Canada", playing: false, volume: 0.28),
        DemoReceiver(id: "demo-upstairs", name: "Upstairs", model: "Speaker group",
                     kind: .speakerGroup, title: "sneakers4free", artist: "Bilderbuch", playing: true, volume: 0.65)
    ]
}
