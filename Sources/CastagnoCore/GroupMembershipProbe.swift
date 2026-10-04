import Foundation
import Security

/// Stereo pairs can report only their virtual ID on the Cast multizone channel.
/// The physical receiver's local setup status supplies its containing groups.
final class GroupMembershipProbe: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let address: String
    private let didUpdate: (ReceiverGroupMembership) -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?

    init(address: String, didUpdate: @escaping (ReceiverGroupMembership) -> Void) {
        self.address = address
        self.didUpdate = didUpdate
    }

    func refresh() {
        guard task == nil, !address.isEmpty else { return }
        var components = URLComponents()
        components.scheme = "https"
        components.host = address.contains(":") ? "[\(address)]" : address
        components.port = 8443
        components.path = "/setup/eureka_info"
        components.queryItems = [URLQueryItem(name: "params", value: "multizone")]
        guard let url = components.url else { return }
        if session == nil {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 3
            configuration.timeoutIntervalForResource = 4
            configuration.urlCache = nil
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        }
        task = session?.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            self.task = nil
            guard error == nil, let response = response as? HTTPURLResponse,
                  response.statusCode == 200, let data,
                  let groups = try? Self.membership(from: data) else { return }
            self.didUpdate(groups)
        }
        task?.resume()
    }

    func stop() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    static func groupIDs(from data: Data) throws -> Set<String> {
        try membership(from: data).groupIDs
    }

    static func membership(from data: Data) throws -> ReceiverGroupMembership {
        struct Status: Decodable {
            struct Multizone: Decodable {
                struct Group: Decodable {
                    let uuid: String
                    let multichannel_group: Bool?
                    let channel_selection: String?
                }
                let groups: [Group]?
                let dynamic_groups: [Group]?
            }
            let multizone: Multizone?
        }
        let status = try JSONDecoder().decode(Status.self, from: data)
        let groups = (status.multizone?.groups ?? []) + (status.multizone?.dynamic_groups ?? [])
        var membership = ReceiverGroupMembership()
        for group in groups {
            let id = GroupVisibility.canonicalID(group.uuid.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !id.isEmpty else { continue }
            membership.groupIDs.insert(id)
            // Use explicit receiver metadata, not member count or matching names.
            if group.multichannel_group == true,
               ["left", "right"].contains(group.channel_selection?.lowercased() ?? "") {
                membership.stereoPairIDs.insert(id)
            }
        }
        return membership
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Cast receivers use self-signed certificates. Trust is limited to this
        // Bonjour-resolved endpoint; setup requests cannot follow redirects.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == address,
              challenge.protectionSpace.port == 8443,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
