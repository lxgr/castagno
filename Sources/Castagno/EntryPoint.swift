import CastagnoCLI
import Foundation

@main
enum EntryPoint {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty || arguments == ["--demo"] {
            CastagnoApp.main()
        } else {
            exit(CastagnoCommandLine.run(arguments))
        }
    }
}
