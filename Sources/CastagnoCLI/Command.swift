import Foundation

enum MuteMode: String { case on, off, toggle }

enum Command: Equatable {
    case help
    case list(all: Bool, timeout: Double)
    case watch(all: Bool, timeout: Double?)
    case volume(id: String, percent: Double, timeout: Double)
    case mute(id: String, mode: MuteMode, timeout: Double)
    case playback(id: String, playing: Bool?, timeout: Double)

    static func parse(_ arguments: [String]) throws -> Command {
        guard let verb = arguments.first else { return .help }
        if ["help", "--help", "-h"].contains(verb) { return .help }
        var positional: [String] = []
        var all = false
        var timeout: Double?
        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--all": all = true
            case "--timeout":
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]),
                      value.isFinite, value > 0, value <= 60 else {
                    throw CLIError("--timeout must be between 0 and 60 seconds")
                }
                timeout = value
            default:
                if token.hasPrefix("--") { throw CLIError("Unknown option: \(token)") }
                positional.append(token)
            }
            index += 1
        }
        switch verb {
        case "list", "status":
            guard positional.isEmpty else { throw CLIError("list takes no positional arguments") }
            return .list(all: all, timeout: timeout ?? 6)
        case "watch":
            guard positional.isEmpty else { throw CLIError("watch takes no positional arguments") }
            return .watch(all: all, timeout: timeout)
        case "volume":
            guard !all, positional.count == 2, !positional[0].isEmpty,
                  let percent = Double(positional[1]), percent.isFinite, (0...100).contains(percent) else {
                throw CLIError("Usage: volume <device-id> <0..100> [--timeout seconds]")
            }
            return .volume(id: positional[0], percent: percent, timeout: timeout ?? 12)
        case "mute":
            guard !all, positional.count == 2, !positional[0].isEmpty,
                  let mode = MuteMode(rawValue: positional[1]) else {
                throw CLIError("Usage: mute <device-id> <on|off|toggle> [--timeout seconds]")
            }
            return .mute(id: positional[0], mode: mode, timeout: timeout ?? 12)
        case "pause", "resume", "play", "toggle":
            guard !all, positional.count == 1, !positional[0].isEmpty else {
                throw CLIError("Usage: \(verb) <device-id> [--timeout seconds]")
            }
            return .playback(id: positional[0], playing: verb == "toggle" ? nil : verb != "pause",
                             timeout: timeout ?? 12)
        default: throw CLIError("Unknown command: \(verb). Use --help.")
        }
    }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
