# Castagno implementation plan

Build a tiny native macOS menu bar utility for Google Cast receiver volume.

- [x] Initialize source control and establish a reproducible Swift Package Manager build (macOS 13+).
- [x] Package OpenCastSwift locally, preserving its MIT license and documenting upstream versions and compatibility patches.
- [x] Discover `_googlecast._tcp` devices, maintain a connection per receiver, and observe receiver volume/mute status without launching a Cast app.
- [x] Build a compact SwiftUI menu bar popover: device name/model, volume slider, mute, retry, scanning/empty/error states, and Quit.
- [x] Bundle the executable as a `.app` with local-network usage metadata and a menu-bar-only activation policy.
- [x] Compile, test framing and volume behavior, and document running and real-device verification.

Hardware verification remains: use the checklist in [DEVELOPMENT.md](DEVELOPMENT.md#real-device-checks) with real Cast receivers.

First release scope: local network receivers and advertised speaker groups, receiver volume/mute, and pause/resume of existing media. No account login, telemetry, or launch-at-login setting.

Bugs/improvement tasks

Always run tests (manual and practical in my network) and commit after checking off one!

Visual inspection is waived at the user's request. Continue using builds, automated tests, and direct network checks.

- [x] Feels like I need to manually press the refresh button to get it going – why?
  - Discovery now starts at app launch, independently of opening the popover. Failed connections automatically retry with bounded backoff; manual Retry and shutdown cancel pending attempts.
  - Verified with 26 passing tests and a read-only live startup/watch run: all four receivers connected and playback updates arrived without refresh. First-opening window sizing is additionally fixed and covered by the later popover regression tests. Visual inspection waived.
- [x] Get rid of the green. Brown should be the theme of the menu bar.
  - Brown accent throughout: volume sliders, connected speakers, playback labels, highlights, and controls. Verified no green remains in the view, 26 tests pass, and the rebuilt bundle connects to all four receivers.
- [x] Bigger popup window, why do I need to scroll so much
  - Increased width from 350 to 420 points and the device-list height limit from 420 to 680 points, bounded by the current screen's usable height. Tests pass and the rebuilt bundle connects to all four receivers; visual inspection waived.
- [x] Too many "network is down" bugs. What's up there? Debug extensively
  - OS logs confirm historical `Local network prohibited` failures. Compared sandboxed/native/Launch Services runs and monitored all four receivers for 60 seconds without native failures. Added structured error/attempt diagnostics, actionable guidance, and optional signing identity support; 31 tests pass. Evidence and remaining signing/lifecycle limits are in [NETWORKING.md](NETWORKING.md).
- [x] I still see grouped devices
  - Fixed stereo-pair membership using physical receivers' local setup status alongside Cast multizone updates. Live verification shows only the stereo pair and standalone display, while `--all` retains both individual speakers; the pair lists both physical member IDs. All 29 tests pass, including stereo-pair regression coverage.
- [x] Remove the "title bar" in the pop-up; we'll save that for an eventual "about" screen. Preserve real estate
  - Removed the logo/name/tagline header and moved refresh beside Quit in the compact footer. 31 tests pass; the rebuilt bundle's live check retains correct grouping and connected receivers. Visual inspection waived.
- [x] Seems a bit too wide now in general. Also the longer help text while scanning does not line wrap and ends in an ellipsis.
  - Reduced width to 380 points while retaining the taller list. Scanning instructions and discovery errors expand vertically and wrap. 31 tests pass and the rebuilt bundle connects with correct grouping; visual inspection waived.
- [x] Ability to pause/resume by clicking the speaker, with some visual affordance of that
  - Speaker icon is a button with a play/pause badge and confirmation spinner. Added core methods and CLI pause/resume/toggle commands, with no app launches or media replacement. All 37 tests pass. A live stereo-pair test confirmed PAUSED then PLAYING and restored the original playback state.
- [x] Search seems to be taking a long time with no progress. Possible to make it streaming?
  - Exposed streaming discovery phases/counts in the UI and JSON, bounded Bonjour resolution to five seconds, and made `list` return settled results early. All 41 tests pass; live results arrived at 0.23 seconds, settled at 2.28 seconds, with correct grouping and connectivity. Browsing continues after settlement.
- [x] Popup with no devices visible and not yet scanning is too small. Maybe fix by just initiating a search once launched if no device found?
  - Empty state has a 240-point minimum content height, and discovery starts at app launch. Fixed the related footer-only first opening: the scroll area now has an explicit content-based height, even if receivers were discovered before opening. A native minimum-size regression test reproduces the old 41-point footer-only layout and passes with the fix. All 43 tests pass, with visual inspection waived.
- [x] A device just paused drops down immediately. Keep the most recently interacted-with device stable somehow.
  - Holds the most recently controlled device at its current row position for 30 seconds; further interactions renew the hold. Pause/expiry, lower-row stability, and external-pause ordering are covered by tests. All 46 tests pass and the rebuilt bundle passes live connectivity/grouping checks.
- [x] Can we distinguish stereo pairs from "true" groups? I feel like people might interpret stereo pairs, especially of the same device type, as one category of thing, but groups as another?
  - Added distinct stereo-pair and speaker-group labels/icons and JSON `kind`/`displayModel`. Classification uses explicit multichannel plus left/right receiver metadata; two matching speakers alone do not imply a pair. All 49 tests pass. Live verification identifies the paired receiver as `stereoPair` with “Nest Audio · Stereo pair” and both physical member IDs. Rebuilt and relaunched outside the sandbox; visual inspection waived.
