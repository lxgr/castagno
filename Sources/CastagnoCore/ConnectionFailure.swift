import Foundation

public struct ConnectionFailure: Codable, Equatable {
    public let domain: String
    public let code: Int
    public let description: String
    public let networkUnavailable: Bool

    init(error: Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
        description = error.localizedDescription
        var current: NSError? = error
        var seen = Set<ObjectIdentifier>()
        var unavailable = false
        while let next = current, seen.insert(ObjectIdentifier(next)).inserted {
            unavailable = unavailable || (next.domain == NSPOSIXErrorDomain && next.code == 50)
                || (next.domain == NSURLErrorDomain && next.code == NSURLErrorNotConnectedToInternet)
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        networkUnavailable = unavailable
    }

    var guidance: String {
        networkUnavailable
            ? "Cannot reach the local network. Check Wi-Fi and Castagno's Local Network access in System Settings."
            : description
    }
}
