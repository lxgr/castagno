import CastagnoCore
import Foundation

public enum CastagnoCommandLine {
    public static func run(_ arguments: [String]) -> Int32 {
        do {
            var arguments = arguments
            var output = FileHandle.standardOutput
            var outputURL: URL?
            if let index = arguments.firstIndex(of: "--output") {
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw CLIError("--output requires a file path")
                }
                let path = arguments[index + 1]
                arguments.removeSubrange(index...(index + 1))
                guard !arguments.contains("--output") else { throw CLIError("Specify --output only once") }
                outputURL = URL(fileURLWithPath: path)
            }
            let command = try Command.parse(arguments)
            if let outputURL, command != .help {
                try Data().write(to: outputURL, options: .atomic)
                output = try FileHandle(forWritingTo: outputURL)
            }
            defer { if outputURL != nil && command != .help { try? output.close() } }
            if command == .help {
                print("""
                Castagno — local Cast discovery, playback status, and volume control

                Usage: Castagno <command>
                  list [--all] [--timeout seconds]    JSON snapshot (default: 6 seconds)
                  status [--all] [--timeout seconds]  Alias for list
                  watch [--all] [--timeout seconds]   JSON updates, one per line
                  volume <device-id> <0..100>         Set receiver volume
                  mute <device-id> <on|off|toggle>    Set receiver mute
                  pause <device-id>                  Pause existing media
                  resume <device-id>                 Resume existing media (alias: play)
                  toggle <device-id>                 Toggle pause/resume
                  --help                             Show help
                  --demo                             Open GUI with fictional devices; no network access

                Controls accept --timeout seconds (default: 12, maximum: 60).
                --all includes speakers hidden by group membership.
                --output FILE writes JSON to a file instead of stdout.
                Playback commands only control existing media; they never launch or replace it.
                Run the bundled executable for local-network permission metadata:
                  dist/Castagno.app/Contents/MacOS/Castagno list
                """)
                return 0
            }

            // The same store, sessions, sorting, and grouping power the SwiftUI app.
            let store = DeviceStore()
            defer { store.shutdown() }
            switch command {
            case .help: return 0
            case .list(let all, let timeout):
                let end = deadline(after: timeout)
                repeat {
                    if store.discoveryError != nil { break }
                    let snapshot = store.snapshot(includeGroupMembers: true)
                    if store.discoveryProgress.phase == .monitoring,
                       snapshot.devices.allSatisfy({ $0.connected }) { break }
                    pump(until: min(end, deadline(after: 0.05)))
                } while ProcessInfo.processInfo.systemUptime < end
                try emit(store.snapshot(includeGroupMembers: all), to: output, pretty: true)
                return store.discoveryError == nil ? 0 : 1
            case .watch(let all, let timeout):
                let end = timeout.map(deadline)
                var last: DiscoverySnapshot?
                repeat {
                    let snapshot = store.snapshot(includeGroupMembers: all)
                    if snapshot != last {
                        try emit(snapshot, to: output)
                        last = snapshot
                    }
                    pump(until: min(end ?? .infinity, deadline(after: 0.2)))
                } while end == nil || ProcessInfo.processInfo.systemUptime < end!
                let finalSnapshot = store.snapshot(includeGroupMembers: all)
                if finalSnapshot != last { try emit(finalSnapshot, to: output) }
                return store.discoveryError == nil ? 0 : 1
            case .volume(let id, let percent, let timeout):
                let end = deadline(after: timeout)
                let session = try waitForSession(id: id, store: store, until: end)
                if let value = session.confirmedVolume, abs(value * 100 - percent) <= 0.0001 {
                    try emit(session.snapshot, to: output, pretty: true)
                    return 0
                }
                let revision = session.statusRevision
                session.setVolume(percent / 100)
                session.setEditing(false)
                try waitForConfirmation(session, until: end) {
                    session.statusRevision > revision
                        && abs((session.confirmedVolume ?? -1) * 100 - percent) <= 1
                }
                try emit(session.snapshot, to: output, pretty: true)
                return 0
            case .mute(let id, let mode, let timeout):
                let end = deadline(after: timeout)
                let session = try waitForSession(id: id, store: store, until: end)
                let target = mode == .toggle ? !session.muted : mode == .on
                if session.muted != target {
                    let revision = session.statusRevision
                    session.setMuted(target)
                    try waitForConfirmation(session, until: end) {
                        session.statusRevision > revision && session.muted == target
                    }
                }
                try emit(session.snapshot, to: output, pretty: true)
                return 0
            case .playback(let id, let playing, let timeout):
                let end = deadline(after: timeout)
                let session = try waitForSession(id: id, store: store, until: end)
                while !session.canControlPlayback && ProcessInfo.processInfo.systemUptime < end {
                    if session.failed { throw CLIError(session.message) }
                    pump(until: min(end, deadline(after: 0.05)))
                }
                let target = playing ?? !session.playback.isPlaying
                guard session.setPlaying(target) else { throw CLIError("No controllable media on \(session.device.name)") }
                while session.playbackActionPending && ProcessInfo.processInfo.systemUptime < end {
                    if session.failed { throw CLIError(session.message) }
                    pump(until: min(end, deadline(after: 0.05)))
                }
                if let error = session.playbackControlError { throw CLIError(error) }
                guard session.playback.state == (target ? .playing : .paused), !session.playbackActionPending else {
                    throw CLIError("Receiver did not confirm playback before timeout")
                }
                try emit(session.snapshot, to: output, pretty: true)
                return 0
            }
        } catch {
            // Machine-readable errors stay on stderr and carry a nonzero exit status.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = (try? encoder.encode(["error": String(describing: error)])) ?? Data()
            FileHandle.standardError.write(data + Data([10]))
            return 1
        }
    }

    private static func waitForSession(id: String, store: DeviceStore, until end: Double) throws -> DeviceSession {
        repeat {
            if let error = store.discoveryError { throw CLIError(error) }
            if let session = store.session(id: id) {
                if session.ready { return session }
            }
            pump(until: min(end, deadline(after: 0.05)))
        } while ProcessInfo.processInfo.systemUptime < end
        throw CLIError(store.session(id: id).flatMap { $0.failed ? $0.message : nil }
                       ?? "Device \(id) was not discovered or connected before timeout")
    }

    private static func waitForConfirmation(_ session: DeviceSession, until end: Double,
                                            confirmed: () -> Bool) throws {
        repeat {
            if confirmed() { return }
            if session.failed { throw CLIError(session.message) }
            pump(until: min(end, deadline(after: 0.05)))
        } while ProcessInfo.processInfo.systemUptime < end
        throw CLIError("Receiver did not confirm the requested change before timeout")
    }

    private static func emit<T: Encodable>(_ value: T, to output: FileHandle, pretty: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        output.write(try encoder.encode(value) + Data([10]))
    }

    private static func deadline(after seconds: Double) -> Double {
        ProcessInfo.processInfo.systemUptime + seconds
    }

    private static func pump(until end: Double) {
        while ProcessInfo.processInfo.systemUptime < end {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: min(0.05, end - ProcessInfo.processInfo.systemUptime)))
        }
    }
}
