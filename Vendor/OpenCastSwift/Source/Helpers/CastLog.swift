import Foundation

/// Keep diagnostic output separate from CLI JSON on stdout.
func castLog(_ items: Any...) {
    let message = items.map { String(describing: $0) }.joined(separator: " ") + "\n"
    FileHandle.standardError.write(Data(message.utf8))
}
