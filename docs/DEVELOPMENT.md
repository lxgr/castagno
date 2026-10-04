# Development and usage

Build, CLI, artwork, and verification details. Run commands from the repository root.

## Build and run

Requires macOS 13+ and Xcode Command Line Tools with Swift 5.9+.

```sh
./scripts/build-app.sh
open dist/Castagno.app
```

Click the chestnut speaker icon in the menu bar. Allow Local Network access when prompted, and keep your Mac and receivers on the same network. Devices appear automatically; each gets a volume slider, mute button, and receiver-confirmed status. Volume requests are coalesced during dragging. The app checks receiver status every five seconds and listens for pushed updates.

The small ⓘ button in the footer opens About Castagno, with the chestnut speaker logo, the MIT license, and the full third-party license notices. The About window stays open independently of the menu bar popover.

Once a speaker group reports its membership, its individual speakers are hidden from the list. Stereo pairs also use the physical receivers' local setup membership, refreshed every 15 seconds, because the pair's Cast status can contain only its own virtual ID. Groups and standalone devices remain visible. Speakers return when they leave all discovered groups or the group disappears from discovery. The setup-status endpoint follows the [PyChromecast protocol reference](https://github.com/home-assistant-libs/pychromecast/blob/master/pychromecast/dial.py).

Stereo pairs have a paired-speaker icon and a “Stereo pair” label, including the shared hardware model when available (for example, “Nest Audio · Stereo pair”). Other groups show a stack icon and “Speaker group.” This distinction comes from explicit multichannel and left/right setup metadata, rather than matching speaker models or a group having two members. CLI snapshots expose `kind` (`device`, `stereoPair`, or `speakerGroup`) and `displayModel`; `isGroup` remains true for both pairs and groups because both use Cast group connections.

Devices reporting active playback appear first and have a brown highlighted card with a Playing indicator. Cards show the media title, artist (when supplied), and Cast app. Paused and buffering sessions are labeled separately. Receivers that do not expose media metadata show their app/status text; merely having an app open does not mark a device as playing.

Discovery starts as soon as the app launches. Failed receiver connections retry automatically, with a delay that increases from 2 seconds to at most 30 seconds. Retry reconnects immediately; the footer refresh button restarts discovery. Networks that isolate clients or block multicast DNS can prevent discovery. Local Network permission can be changed in System Settings → Privacy & Security → Local Network.

If you see “Network is down,” inspect `connectionAttempts` and `lastConnectionError` in CLI JSON. The OS can report that error for local-network permission denial. See [NETWORKING.md](NETWORKING.md) for the tested diagnosis, logging commands, and optional `CASTAGNO_SIGN_IDENTITY` build setting.

The build script produces an ad hoc signed app for local use on the current Mac architecture. Published releases target Apple Silicon only; Developer ID signing and notarization remain future work. Run the bundled app to get the proper macOS permission identity; `swift run` does not provide the bundle's usage metadata.

## Screenshot demo

Quit the running app, then launch the offline scene:

```sh
open -n dist/Castagno.app --args --demo
```

The scene contains Living Room (stereo pair, playing “Islands of Men” by Geese), Kitchen (Google Nest Hub, paused on “Olson” by Boards of Canada), and Upstairs (speaker group, playing “sneakers4free” by Bilderbuch). These are fictional receivers. Volume, mute, and playback controls work locally; refresh resets the scene. No network discovery or Cast connections are started. Quit and launch normally to use real devices again.

## CLI and testing

An iOS companion app, widget, and Control Center controls are explored in [IOS-EXPLORATION.md](IOS-EXPLORATION.md), including platform limits and the proposed validation work. This is an exploration, not an implemented port.

The menu bar is a client of the standalone `CastagnoCore` library. The bundled executable also exposes the same core as a CLI, without starting the GUI:

```sh
./scripts/castagnoctl.sh list --timeout 6
./scripts/castagnoctl.sh list --all --timeout 6
./scripts/castagnoctl.sh watch --timeout 10
./scripts/castagnoctl.sh volume DEVICE_ID 35
./scripts/castagnoctl.sh mute DEVICE_ID on
```

`list` emits a JSON snapshot, including playback and confirmed volume state. It returns once initial discovery has been quiet for two seconds and receivers are connected; `--timeout` is the maximum wait. `watch` immediately streams JSON changes, one per line, including discovery phase and found/resolving/failed counts. The popover shows devices as each resolves, displays scan progress, and keeps watching for new receivers after the initial scan settles. Individual Bonjour resolution waits are capped at five seconds.

Volume/mute and playback commands wait for receiver confirmation and fail with a nonzero exit code on timeout. `--all` includes individual speakers hidden by group filtering. Use `--help` for all options. Commands discover the network directly, so the GUI does not need to be running. See [ARCHITECTURE.md](ARCHITECTURE.md).

Click a speaker's play/pause badge to pause or resume its existing media. Idle receivers have no playback button action. The same controls are available headlessly:

```sh
./scripts/castagnoctl.sh pause <device-id>
./scripts/castagnoctl.sh resume <device-id>
./scripts/castagnoctl.sh toggle <device-id>
```

Controls never launch a Cast app or load a new track. The icon shows a spinner while waiting for confirmation and allows retry after an error.

The most recently controlled device stays at its current row position for 30 seconds, so pausing it doesn't move the button away from your pointer. Further interactions renew the hold. Other devices continue to sort by playback activity; normal sorting resumes when the hold expires.

For a scan launched through macOS Launch Services, JSON can be written directly to a file:

```sh
open -n -W dist/Castagno.app --args list --all --timeout 6 --output /tmp/castagno-status.json
cat /tmp/castagno-status.json
```

Snapshots include the resolved host/address/port and connection errors for diagnostics. Discovery can succeed even when native socket access is unavailable; inspect `connected`, `failed`, and `connectionStatus` before using controls.

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox --build-system native
```

Open `Package.swift` in Xcode to edit the project. Dependencies are vendored, so builds need no dependency downloads. Versions, licenses, and compatibility changes are documented in [Vendor/README.md](../Vendor/README.md).

## Icons

The editable SVG masters are [ChestnutSpeaker.svg](../Resources/Icons/ChestnutSpeaker.svg) and [MenuBar.svg](../Resources/Icons/MenuBar.svg). The generator composes a standalone `AppIcon.svg` from the speaker artwork, renders PNGs with CairoSVG, and packages the macOS `.icns`. The menu bar uses native 1×/2× template images that adapt to the system appearance. Generated assets are checked in, so normal app builds require no image tools.

To edit and regenerate the icons, install the renderer once (requires the Cairo library, available with `brew install cairo`):

```sh
python3 -m pip install --target .build/icon-tools cairosvg==2.9.1
```

Then regenerate the bundled `.icns`, PNG exports, and design preview:

```sh
./scripts/generate-icons.sh
./scripts/build-app.sh
```

See [the icon preview](../Resources/Icons/Preview.png) for the app icon and menu bar symbol at small sizes.

## License

Castagno's original code and artwork are licensed under [MIT](../LICENSE). Vendored components retain their own licenses, reproduced in [THIRD-PARTY-NOTICES.txt](../THIRD-PARTY-NOTICES.txt). The build synchronizes both files into the app's resource bundle for About and includes them in the distributed app.

## Real-device checks

1. Launch the app and allow network access. Confirm named receivers and groups appear.
2. Move a slider and check the device's actual volume. Mute/unmute and verify the device responds.
3. Change volume in Google Home or another Cast controller and confirm Castagno updates.
4. Power off a receiver or disconnect Wi-Fi. Confirm it disappears or shows a connection failure; restore it and confirm it reconnects automatically. Retry should reconnect immediately, without waiting for the next scheduled attempt.
5. Quit and relaunch; confirm only the menu bar icon appears and existing Cast playback continues.
6. Play media on a receiver: confirm its card moves to the top, highlights brown, and shows its title/artist. Use the speaker badge to pause/resume, change tracks, and close the Cast app; confirm the indicator and metadata update.

Automated tests cover fragmented Cast frames, unaligned headers, buffer compaction, invalid frame sizes, volume bounds, receiver-targeted commands, group membership filtering and updates, playback ordering, and metadata updates. Hardware behavior still requires a Cast device on the local network.

Validated: debug and release compilation, 49 core/CLI/layout tests, bundle plist, and code signature. Native network checks connected to all four receivers, read confirmed volume/mute and Spotify metadata, hid the individual speakers under their stereo pair, classified it as a Nest Audio stereo pair, and confirmed a pause/resume cycle with the original playback restored. Streaming discovery produced results at 0.23 seconds and settled at 2.28 seconds; a snapshot returned in 2.28 seconds rather than waiting its eight-second timeout. A 60-second watch observed no connection failures. Layout regression tests reproduce the former 41-point footer-only window under a minimum-height proposal and verify the fixed device list and empty state remain visible on first opening. Volume/mute mutation, sleep/network switching, and future permission persistence remain hardware checks. Visual inspection is waived at the user's request.
