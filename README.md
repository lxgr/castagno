# Castagno

A tiny macOS menu bar app for Google Cast speakers, stereo pairs, and groups. Adjust volume, mute, pause/resume, and see what's playing.

<img src="screenshot.png" alt="Castagno in action" width="400">

## Run

Requires macOS 13+ and Xcode Command Line Tools with Swift 5.9+.

```sh
./scripts/build-app.sh
open dist/Castagno.app
```

Click the chestnut speaker in your menu bar. Keep your Mac and receivers on the same network, and allow Local Network access when prompted.

See [the documentation](docs/INDEX.md) for development, CLI commands, troubleshooting, and future explorations.

[MIT](LICENSE) · Built with [OpenCastSwift](https://github.com/SuperMarcus/OpenCastSwift) · [Third-party licenses](THIRD-PARTY-NOTICES.txt)
