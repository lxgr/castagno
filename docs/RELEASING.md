# Releases and Homebrew

Published builds target macOS 13+ on Apple Silicon only. Intel builds are not distributed.

## Build and package

Run tests, then package on an arm64 Mac:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox --build-system native
./scripts/package-release.sh
```

The script builds the app, verifies its signature and arm64 architecture, and creates `dist/Castagno-VERSION-macos-arm64.zip` plus `dist/SHA256SUMS`. The ZIP contains `Castagno.app` and `allow-castagno.sh`; build output remains ignored by Git. Version and build number come from `Resources/Info.plist`.

Create a GitHub release in [lxgr/castagno](https://github.com/lxgr/castagno/releases), uploading the ZIP and checksum file. Update `version` and `sha256` in `Casks/castagno.rb` in [lxgr/homebrew-tap](https://github.com/lxgr/homebrew-tap) to match the immutable release asset. The cask requires Apple Silicon and macOS Ventura or later.

## Signing and quarantine

The default build uses `codesign --sign -`, an ad hoc signature without a certificate. Apple Silicon requires signed native code, and ad hoc signing meets that execution requirement. A self-signed certificate is unnecessary for this distribution path. See [Apple's code-signing requirements](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes).

Ad hoc signing does not provide a trusted developer identity or notarization. The cask runs the release's `allow-castagno.sh` on the staged app before installation. This checks the bundle identifier and signature, then removes only `com.apple.quarantine` recursively from that app. It does not disable Gatekeeper globally, alter other apps, or remove other extended attributes. The cask and installation instructions disclose this behavior.

For a manual ZIP installation, move the app into Applications and run the included script:

```sh
sh allow-castagno.sh /Applications/Castagno.app
open /Applications/Castagno.app
```

Local Network permission is still required. Ad hoc identity can change across app updates, so macOS may request permission again; see [NETWORKING.md](NETWORKING.md). Removing quarantine is not a substitute for code-signature integrity or a guarantee of launch under every managed Mac policy.

For a future notarized release, use an Apple-issued Developer ID Application certificate, hardened runtime, secure timestamp, and Apple's notary service, then remove the quarantine-removal hook from the tap. The current build script's optional signing identity alone is not a complete notarization pipeline. See [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
