import Foundation

public struct DiscoverySnapshot: Codable, Equatable {
    public let devices: [DeviceSnapshot]
    public let discoveryError: String?
    public let discovery: DiscoveryProgress

    public init(devices: [DeviceSnapshot], discoveryError: String? = nil,
                discovery: DiscoveryProgress = DiscoveryProgress()) {
        self.devices = devices
        self.discoveryError = discoveryError
        self.discovery = discovery
    }
}

public struct DeviceSnapshot: Codable, Equatable {
    public let id: String
    public let name: String
    public let model: String
    public let host: String
    public let address: String
    public let port: Int
    public let isGroup: Bool
    public let kind: ReceiverKind
    public let displayModel: String
    public let memberIDs: [String]
    public let connected: Bool
    public let failed: Bool
    public let connectionStatus: String
    public let volumePercent: Double?
    public let muted: Bool?
    public let isPlaying: Bool
    public let playbackState: String?
    public let title: String?
    public let detail: String?
    public let connectionAttempts: Int
    public let lastConnectionError: ConnectionFailure?
    public let canControlPlayback: Bool
    public let playbackActionPending: Bool
    public let playbackControlError: String?
}

extension DeviceSession {
    public var snapshot: DeviceSnapshot {
        snapshot(memberIDs: nil)
    }

    func snapshot(memberIDs: [String]?) -> DeviceSnapshot {
        DeviceSnapshot(id: id, name: device.name, model: device.modelName,
                       host: device.hostName, address: device.ipAddress, port: device.port,
                       isGroup: device.isGroup, kind: kind, displayModel: displayModel,
                       memberIDs: memberIDs ?? groupMemberIDs.sorted(),
                       connected: ready, failed: failed, connectionStatus: message,
                       volumePercent: confirmedVolume.map { $0 * 100 }, muted: ready ? muted : nil,
                       isPlaying: playback.isPlaying, playbackState: playback.state?.rawValue,
                       title: playback.title, detail: playback.detail,
                       connectionAttempts: connectionAttempts, lastConnectionError: lastConnectionError,
                       canControlPlayback: canControlPlayback, playbackActionPending: playbackActionPending,
                       playbackControlError: playbackControlError)
    }
}
