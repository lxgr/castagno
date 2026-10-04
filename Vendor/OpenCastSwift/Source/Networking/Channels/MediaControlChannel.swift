//
//  MediaControlChannel.swift
//  OpenCastSwift
//
//  Created by Miles Hollingsworth on 4/22/18
//  Copyright © 2018 Miles Hollingsworth. All rights reserved.
//

import Foundation
import SwiftyJSON

class MediaControlChannel: CastChannel {
    private var cachedStatus: [String: Any] = [:]
    private var observedApp: CastApp?

    func observe(_ app: CastApp?) {
        if observedApp?.transportId != app?.transportId || observedApp?.sessionId != app?.sessionId {
            cachedStatus = [:]
        }
        observedApp = app
    }
    private var delegate: MediaControlChannelDelegate? {
        return requestDispatcher as? MediaControlChannelDelegate
    }

    init() {
        super.init(namespace: CastNamespace.media)
    }

    override func handleResponse(_ json: JSON, sourceId: String) {
        guard let rawType = json["type"].string else { return }

        guard let type = CastMessageType(rawValue: rawType) else {
            castLog("Unknown type: \(rawType)")
            castLog(json)
            return
        }

        switch type {
        case .mediaStatus:
            if let app = observedApp, sourceId != app.transportId { return }
            guard let statuses = json["status"].array else { return }
            guard let status = statuses.first else {
                cachedStatus = [:]
                delegate?.channel(self, didReceive: CastMediaStatus(json: JSON(["playerState": "IDLE"]), sourceId: sourceId))
                return
            }
            let incoming = status.dictionaryObject ?? [:]
            if let sessionId = status["mediaSessionId"].int,
               sessionId != JSON(cachedStatus)["mediaSessionId"].int {
                cachedStatus = [:]
            }
            var merged = cachedStatus.merging(incoming) { _, new in new }
            if let media = incoming["media"] as? [String: Any] {
                let oldMedia = cachedStatus["media"] as? [String: Any] ?? [:]
                let changedContent = media["contentId"] != nil
                    && JSON(media)["contentId"].string != JSON(oldMedia)["contentId"].string
                merged["media"] = (changedContent ? [:] : oldMedia).merging(media) { _, new in new }
            }
            cachedStatus = merged
            delegate?.channel(self, didReceive: CastMediaStatus(json: JSON(merged), sourceId: sourceId))

        default:
            castLog(rawType)
        }
    }

    public func requestMediaStatus(for app: CastApp, completion: ((Result<CastMediaStatus, CastError>) -> Void)? = nil) {
        let payload: [String: Any] = [
            CastJSONPayloadKeys.type: CastMessageType.statusRequest.rawValue,
            CastJSONPayloadKeys.sessionId: app.sessionId
        ]

        let request = requestDispatcher.request(withNamespace: namespace,
                                                destinationId: app.transportId,
                                                payload: payload)

        if let completion = completion {
            send(request) { result in
                switch result {
                case .success(let json):
                    guard let status = json["status"].array?.first else {
                        completion(.failure(.session("No media playing")))
                        return
                    }
                    completion(.success(CastMediaStatus(json: status)))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            send(request)
        }
    }

    public func sendPause(for app: CastApp, mediaSessionId: Int) {
        send(.pause, for: app, mediaSessionId: mediaSessionId)
    }

    public func sendPlay(for app: CastApp, mediaSessionId: Int) {
        send(.play, for: app, mediaSessionId: mediaSessionId)
    }

    public func sendStop(for app: CastApp, mediaSessionId: Int) {
        send(.stop, for: app, mediaSessionId: mediaSessionId)
    }

    public func sendSeek(to currentTime: Float, for app: CastApp, mediaSessionId: Int) {
        let payload: [String: Any] = [
            CastJSONPayloadKeys.type: CastMessageType.seek.rawValue,
            CastJSONPayloadKeys.sessionId: app.sessionId,
            CastJSONPayloadKeys.currentTime: currentTime,
            CastJSONPayloadKeys.mediaSessionId: mediaSessionId
        ]

        let request = requestDispatcher.request(withNamespace: namespace,
                                                destinationId: app.transportId,
                                                payload: payload)

        send(request)
    }

    private func send(_ message: CastMessageType, for app: CastApp, mediaSessionId: Int) {
        let payload: [String: Any] = [
            CastJSONPayloadKeys.type: message.rawValue,
            CastJSONPayloadKeys.mediaSessionId: mediaSessionId
        ]

        let request = requestDispatcher.request(withNamespace: namespace,
                                                destinationId: app.transportId,
                                                payload: payload)

        send(request)
    }

    public func load(media: CastMedia, with app: CastApp, completion: @escaping (Result<CastMediaStatus, CastError>) -> Void) {
        var payload = media.dict
        payload[CastJSONPayloadKeys.type] = CastMessageType.load.rawValue
        payload[CastJSONPayloadKeys.sessionId] = app.sessionId

        let request = requestDispatcher.request(withNamespace: namespace,
                                                destinationId: app.transportId,
                                                payload: payload)

        send(request) { result in
            switch result {
            case .success(let json):
                guard let status = json["status"].array?.first else { return }

                completion(.success(CastMediaStatus(json: status)))

            case .failure(let error):
                completion(.failure(CastError.load(error.localizedDescription)))
            }
        }
    }
}

protocol MediaControlChannelDelegate: AnyObject {
    func channel(_ channel: MediaControlChannel, didReceive mediaStatus: CastMediaStatus)
}
