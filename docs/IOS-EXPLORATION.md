# iOS widgets and Control Center exploration

Status: feasibility exploration, recorded 2026-10-04. No iOS implementation or hardware validation has been performed. The current app remains macOS-only.

## Feasibility

An iOS companion app with a Home Screen widget and Control Center controls appears feasible for bounded Cast actions. Neither surface can reproduce the menu bar app's combination of draggable sliders, continuous discovery, and live playback monitoring.

| Surface | Suitable features | Constraints |
| --- | --- | --- |
| Home Screen widget | Configured favorite speakers, volume −/+, mute, pause/resume, last-known track and volume | Interactive buttons and toggles; no supported draggable volume slider. Background status can become stale. |
| Control Center | A configured speaker's volume up/down, mute, playback toggle, or volume preset | Public control templates are buttons and toggles, rather than custom sliders or a device browser. |
| Full iOS app | Discovery, device selection, live sliders and playback status while active | Cannot assume continuous discovery or receiver connections after the app is suspended. |

Interactive widgets use App Intents to perform actions without launching the app. Control Center controls, introduced in iOS 18, also use App Intents. Their documented templates are `ControlWidgetButton` and `ControlWidgetToggle`; Apple's native volume slider is not a public custom-control template. See [widget interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [controls](https://developer.apple.com/documentation/widgetkit/controls-collection), and [the controls introduction](https://developer.apple.com/videos/play/wwdc2024/10157/).

## Networking and freshness

A widget extension is not continually active, even when visible. WidgetKit budgets background timeline refreshes, so the five-second polling used by the Mac app cannot carry over. Track titles, playback highlights, and volume should be presented as last-known state with a last-checked time. User-triggered App Intent actions can update state and cause a widget timeline reload; those reloads do not count against the normal refresh budget. See [keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/).

Networking in widget extensions is allowed, but extension lifetime and resources are limited. Apple's support for background URLSession downloads does not establish that a long-lived Cast TCP/TLS connection is viable. A short connect–command–confirm transaction is the proposed approach, subject to testing on iOS devices. See [network requests in widget extensions](https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension).

The containing app should request Local Network permission during foreground onboarding and discover receivers there. Extensions generally share the containing app's Local Network privilege. A background operation with permission still undetermined may be denied without a prompt. Apple instructs apps to put `NSLocalNetworkUsageDescription` and `NSBonjourServices` in the containing app's Info.plist, rather than the extension's. See [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Proposed architecture

The full app would handle permission, discovery, and favorite selection. Shared App Group storage would hold selected receiver IDs, their last resolved endpoints, and timestamped snapshots. Stable receiver IDs would remain the identity; cached IP addresses would only be connection hints because addresses can change.

Each widget or Control Center action would:

1. Retrieve the configured receiver and its cached endpoint.
2. Connect with a bounded timeout, using bounded Bonjour rediscovery if the endpoint is stale.
3. Read receiver state before applying a relative change such as volume +5 percentage points; never calculate it from a stale widget snapshot.
4. Send the command and wait for receiver confirmation.
5. Save the confirmed snapshot, request the applicable UI refresh, and close the connection.

Failures should leave confirmed state intact and provide a retry or a route into the app. Rapid repeated volume taps need explicit serialization or coalescing so separate intent executions do not race. A command that times out after transmission has an uncertain outcome; blindly retrying a relative increment could apply it twice.

`CastagnoCore` already separates protocol behavior from the macOS UI and exposes snapshots and confirmed commands. That is a useful reuse boundary, but it is not yet an iOS port. `Package.swift` currently declares only macOS, and the current sessions assume a main run loop, persistent connections, polling, and automatic reconnection. An iOS adapter would need bounded transaction lifecycle management, cancellation, and app/extension process handling. The CLI and AppKit menu bar would remain separate from the iOS targets. See [ARCHITECTURE.md](ARCHITECTURE.md).

## Questions to validate before committing to a product

- Does the vendored OpenCastSwift transport compile and complete receiver and media commands reliably in an iOS App Intent execution context?
- What are cold-connect and rediscovery latency on real Wi-Fi networks, and can commands finish within the available execution window?
- How do permission denial, locked-device interactions, suspension, network switching, and changed receiver addresses behave?
- Can rapid volume taps across app and extension processes be serialized safely, while retaining receiver confirmation?
- Do speaker groups and stereo-pair membership probes work within the same bounded lifecycle?
- How fresh can widget and Control Center state realistically be, and how should stale or unavailable state be shown?

These are implementation experiments, not guarantees established by the documentation. They can be exercised through core-level integration tests and real-device intent invocations before polishing the UI.

## Candidate scope

The most promising first scope is a full app for setup and live sliders, plus a favorite-speaker widget with volume − / mute / +. Control Center could add configured per-speaker quick actions. Playback actions and last-known track metadata could follow once execution and freshness are understood.

If a draggable volume slider directly inside the widget or Control Center is a requirement, the documented public APIs do not meet it. The full app would provide that interaction.
