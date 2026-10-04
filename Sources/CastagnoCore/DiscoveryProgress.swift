import Foundation

public struct DiscoveryProgress: Codable, Equatable {
    public enum Phase: String, Codable { case searching, resolving, monitoring, failed, stopped }
    public var phase: Phase
    public var foundServices: Int
    public var resolvingServices: Int
    public var failedServices: Int
    public var discoveredDevices: Int

    public var isBusy: Bool { phase == .searching || phase == .resolving }
    public var message: String {
        switch phase {
        case .searching: return "Searching local network…"
        case .resolving: return "\(foundServices) found · \(resolvingServices) resolving…"
        case .monitoring:
            return discoveredDevices == 0 ? "No Cast devices found" : "Watching for new devices"
        case .failed: return "Discovery unavailable"
        case .stopped: return "Discovery stopped"
        }
    }

    public init(phase: Phase = .searching, foundServices: Int = 0, resolvingServices: Int = 0,
                failedServices: Int = 0, discoveredDevices: Int = 0) {
        self.phase = phase
        self.foundServices = foundServices
        self.resolvingServices = resolvingServices
        self.failedServices = failedServices
        self.discoveredDevices = discoveredDevices
    }
}
