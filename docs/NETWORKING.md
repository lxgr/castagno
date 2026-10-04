# Network-down investigation

Checked on 2026-10-04 using the bundled CLI, direct launches, Launch Services, a sandboxed comparison, system logs, code-signing requirements, and the four local receivers.

The historical failure is a macOS local-network policy denial. At 11:28:23 the Castagno system log records `unsatisfied (Local network prohibited)` for both IPv4 and IPv6 paths, followed by `Network is down`. That message did not indicate that the Wi-Fi network or all receivers were offline. Bonjour discovery and a reachable TCP port alone do not prove that this process is permitted to connect.

| Check | Result |
| --- | --- |
| Sandboxed bundled CLI | Bonjour fails with error -72000, domain 10; no receivers discovered |
| Direct bundled CLI outside sandbox | Four receivers connected; confirmed volume/mute and media status read |
| Launch Services bundled CLI outside sandbox | Four receivers connected; stereo membership verified |
| 60-second live watch outside sandbox | All four connected after startup, with no observed failures |
| Bundle signing requirement | Ad hoc, bound to the executable's code-directory hash |
| Available code-signing identities | No valid signing identities installed |

Apple's [local-network privacy guidance](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) explains that permissions follow the responsible app/process and code identity. Apple recommends an Apple-issued signing identity for reliable tracking; ad hoc builds can behave inconsistently. Changing build signatures is a plausible contributor to repeated permission trouble here, but the logs do not prove that every earlier failure had that cause.

## Changes

- Discovery starts at app launch and receiver connections recover automatically with 2–30 second backoff. A first failed attempt no longer remains stuck until refresh.
- JSON snapshots include `connectionAttempts` and `lastConnectionError` (domain, code, description, network-unavailable classification). The last error remains available after recovery.
- Connection failures log the receiver, endpoint, attempt count, domain, and code to stderr, keeping JSON stdout clean.
- Network-down errors advise checking Wi-Fi and Castagno's Local Network permission rather than implying that the receiver is offline. Error 50 alone does not distinguish an actual route outage from policy denial.
- `CASTAGNO_SIGN_IDENTITY` selects a signing identity for the bundler; local builds retain the ad hoc default. No signing certificate or system privacy setting was created or modified.

## Reproduce without Computer Use

Run the commands below from the repository root. Build and launch the `.app` outside restrictive execution sandboxes. Inspect local-network failures with:

```sh
./scripts/castagnoctl.sh watch --all --timeout 60 > /tmp/castagno-watch.ndjson 2> /tmp/castagno-network.log
/usr/bin/log show --last 10m --style compact \
  --predicate 'process == "Castagno" AND (eventMessage CONTAINS[c] "Network is down" OR eventMessage CONTAINS[c] "prohibited" OR eventMessage CONTAINS[c] "unsatisfied")'
codesign -d -r- dist/Castagno.app
```

If the OS says `Local network prohibited`, check System Settings → Privacy & Security → Local Network for Castagno and the app responsible for launching a CLI subprocess. If a signing identity is already installed, build with:

```sh
CASTAGNO_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build-app.sh
```

The investigation does not establish long-term stability through sleep, network switching, or future ad hoc rebuilds. Those remain hardware/lifecycle checks; the current native connection and minute-long observation succeeded.
