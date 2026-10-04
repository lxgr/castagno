// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Castagno",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Castagno", targets: ["Castagno"]),
               .library(name: "CastagnoCore", targets: ["CastagnoCore"])],
    targets: [
        .target(name: "SwiftyJSON", path: "Vendor/SwiftyJSON/Source",
                exclude: ["Info-iOS.plist", "Info-macOS.plist", "Info-tvOS.plist", "Info-watchOS.plist", "SwiftyJSON/PrivacyInfo.xcprivacy"]),
        .target(name: "SwiftProtobuf", path: "Vendor/SwiftProtobuf/SwiftProtobuf"),
        .target(name: "OpenCastSwift", dependencies: ["SwiftyJSON", "SwiftProtobuf"],
                path: "Vendor/OpenCastSwift/Source",
                exclude: ["Supporting Files", "Helpers/Proto/cast_channel.proto"]),
        .target(name: "CastagnoCore", dependencies: ["OpenCastSwift"]),
        .target(name: "CastagnoCLI", dependencies: ["CastagnoCore"]),
        .executableTarget(name: "Castagno", dependencies: ["CastagnoCore", "CastagnoCLI"],
                          resources: [.process("Resources")]),
        .testTarget(name: "CastagnoTests", dependencies: ["CastagnoCore", "CastagnoCLI", "OpenCastSwift", "SwiftyJSON"]),
        .testTarget(name: "CastagnoLayoutTests", dependencies: ["Castagno", "CastagnoCore", "OpenCastSwift"])
    ],
    swiftLanguageVersions: [.v5]
)
