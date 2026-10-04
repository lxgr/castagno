# Vendored dependencies

Sources are included so builds do not require Carthage or network access.

- OpenCastSwift: https://github.com/SuperMarcus/OpenCastSwift, revision `d49b0be48aa41fad054c97d5094caebc6ec9befa` (archive downloaded 2026-10-04). Fork of mhmiles/OpenCastSwift, MIT. Only `Source` and license retained.
- SwiftyJSON: https://github.com/SwiftyJSON/SwiftyJSON, 5.0.2 (`af76cf3`), MIT.
- SwiftProtobuf: https://github.com/apple/swift-protobuf, 1.7.0 (`da75a93`), Apache 2.0 with Runtime Library Exception. Runtime sources only, matching the generated Cast protocol source.

The Cast protocol definitions and generated source also retain Chromium's BSD 3-Clause notice in `OpenCastSwift/Chromium-LICENSE` (license text from Chromium 30.0.1599.101). SwiftProtobuf's generated Google protocol definitions retain the BSD 3-Clause notice in `SwiftProtobuf/Protobuf-LICENSE`. All five notices are reproduced in the root `THIRD-PARTY-NOTICES.txt` and in the app's About window. SwiftProtobuf 1.7.0 has no separate upstream NOTICE file.

Castagno patches OpenCastSwift's stream lifecycle to run on the main run loop, buffer partial writes, safely decode framing headers, cancel heartbeat timers on disconnect, and defensively parse Bonjour records. Public receiver-status refresh and discovery-failure callbacks are added. Multizone status is exposed through a callback, updated for member added/updated/removed events, and refreshed alongside receiver status. Clients must be operated on the main thread. This library preserves upstream's Cast TLS configuration (receivers use self-signed certificates).

The CastDevice initializer is public so the core can construct fictional demo receivers without Bonjour or a live network connection.
