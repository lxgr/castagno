//
//  CastV2PlatformReader.swift
//  OpenCastSwift Mac
//
//  Created by Miles Hollingsworth on 4/22/18
//  Copyright © 2018 Miles Hollingsworth. All rights reserved.
//

let maxBufferLength = 8192

import Foundation

class CastV2PlatformReader {
    let stream: InputStream?
    var readPosition = 0
    var buffer = Data(capacity: maxBufferLength)

    init(stream: InputStream? = nil) {
        self.stream = stream
    }

    func append(_ data: Data) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        buffer.append(data)
    }

    func readStream() {
        guard let stream else { return }
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        var totalBytesRead = 0
        let bufferSize = 32

        while stream.hasBytesAvailable {
            var bytes = [UInt8](repeating: 0, count: bufferSize)

            let bytesRead = stream.read(&bytes, maxLength: bufferSize)

            if bytesRead <= 0 { break }

            buffer.append(Data(bytes: &bytes, count: bytesRead))

            totalBytesRead += bytesRead
        }
    }

    func nextMessage() -> Data? {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        let headerSize = MemoryLayout<UInt32>.size
        guard buffer.count - readPosition >= headerSize else { return nil }
        // Data storage need not be aligned to UInt32.
        let payloadSize = buffer[readPosition..<(readPosition + headerSize)]
            .reduce(0) { ($0 << 8) | Int($1) }
        guard payloadSize <= 1_048_576 else {
            buffer.removeAll()
            readPosition = 0
            return nil
        }

        readPosition += headerSize

        guard buffer.count >= readPosition + payloadSize, buffer.count - readPosition >= payloadSize, payloadSize >= 0 else {
            //Message hasn't arrived
            readPosition -= headerSize
            return nil
        }

        let payload = buffer.withUnsafeBytes({ pointer -> Data in
            return Data(bytes: pointer.baseAddress!.advanced(by: self.readPosition), count: payloadSize)
        })
        readPosition += payloadSize

        resetBufferIfNeeded()

        return payload
    }

    private func resetBufferIfNeeded() {
        guard buffer.count >= maxBufferLength else { return }

        if readPosition == buffer.count {
            buffer = Data(capacity: maxBufferLength)
        } else {
            buffer = buffer.advanced(by: readPosition)
        }

        readPosition = 0
    }
}
