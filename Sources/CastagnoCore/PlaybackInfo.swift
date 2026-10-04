import Foundation
import OpenCastSwift

public struct PlaybackInfo: Equatable {
    public var state: CastMediaPlayerState?
    public var title: String?
    public var detail: String?

    public var isPlaying: Bool { state == .playing }
    public var label: String {
        switch state {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .buffering: return "Buffering"
        default: return ""
        }
    }

    public init(app: CastApp? = nil, media: CastMediaStatus? = nil) {
        guard let app, !app.isIdleScreen else { return }
        state = media?.playerState
        guard state != .idle && state != .stopped else { return }
        title = Self.text(media?.metadata?["title"].string)
            ?? Self.text(app.statusText) ?? Self.text(app.displayName)
        let artist = Self.text(media?.metadata?["artist"].string)
            ?? Self.text(media?.metadata?["subtitle"].string)
            ?? Self.text(media?.metadata?["seriesTitle"].string)
        let source = Self.text(app.displayName)
        detail = [artist, source].compactMap { $0 }.filter { $0 != title }.joined(separator: " · ")
        if detail?.isEmpty == true { detail = nil }
    }

    private static func text(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

enum DeviceOrdering {
    static func precedes(playing: Bool, name: String, id: String,
                         otherPlaying: Bool, otherName: String, otherID: String) -> Bool {
        if playing != otherPlaying { return playing }
        let comparison = name.localizedStandardCompare(otherName)
        return comparison == .orderedSame ? id < otherID : comparison == .orderedAscending
    }
}
