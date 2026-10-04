import Foundation

public enum ReceiverKind: String, Codable {
    case device
    case stereoPair
    case speakerGroup

    public var symbol: String {
        switch self {
        case .device: return "hifispeaker.fill"
        case .stereoPair: return "hifispeaker.2.fill"
        case .speakerGroup: return "square.stack.3d.up.fill"
        }
    }
}

struct ReceiverGroupMembership: Equatable {
    var groupIDs: Set<String> = []
    var stereoPairIDs: Set<String> = []
}
