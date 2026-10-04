import AppKit
import SwiftUI
import CastagnoCore

struct DeviceListView: View {
    @ObservedObject var store: DeviceStore
    @State private var deviceContentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.discoveryError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding()
            }

            if store.devices.isEmpty {
                VStack(spacing: 12) {
                    if store.discoveryProgress.isBusy {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 30)).foregroundStyle(.secondary)
                    }
                    Text(store.discoveryProgress.isBusy ? "Looking for Cast devices…" : store.discoveryProgress.message)
                        .font(.headline)
                    Text("Connect your Mac and speakers to the same network. Allow Local Network access when prompted.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.discoveryProgress.phase == .monitoring {
                        Text("Still watching for new devices.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 26).padding(.vertical, 32)
                .frame(minHeight: 240)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.devices) { DeviceRow(session: $0) }
                    }
                    .padding(14)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: DeviceContentHeight.self, value: geometry.size.height)
                        }
                    }
                }
                // MenuBarExtra sizes its window from this view's ideal size.
                // A ScrollView with only maxHeight can collapse to zero when
                // devices are already present on the first opening.
                .frame(height: deviceListHeight)
                .onPreferenceChange(DeviceContentHeight.self) { height in
                    if height > 0 { deviceContentHeight = height }
                }
            }

            Divider()
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    if store.discoveryProgress.isBusy { ProgressView().controlSize(.mini) }
                    Text(discoveryMessage)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { AboutWindowController.shared.present() } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("About Castagno")
                .accessibilityLabel("About Castagno and licenses")
                Button { store.rescan() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(store.isDemo ? "Reset demo scene" : "Scan again")
                .accessibilityLabel(store.isDemo ? "Reset demo scene" : "Scan for Cast devices again")
                Button("Quit") {
                    store.shutdown()
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 380)
        .tint(.brown)
    }

    private var discoveryMessage: String {
        let progress = store.discoveryProgress
        if progress.isBusy || store.devices.isEmpty || progress.phase == .failed { return progress.message }
        let count = "\(store.devices.count) Cast device\(store.devices.count == 1 ? "" : "s")"
        return progress.failedServices > 0 ? "\(count) · \(progress.failedServices) unresolved" : count
    }

    private var deviceListHeight: CGFloat {
        let maximum = max(240, min(680, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
        let initial = CGFloat(store.devices.count) * 120 + 28
        return min(maximum, max(120, deviceContentHeight > 0 ? deviceContentHeight : initial))
    }
}

private struct DeviceContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct DeviceRow: View {
    @ObservedObject var session: DeviceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { session.togglePlayback() } label: {
                    Image(systemName: session.kind.symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(session.ready ? Color.brown : Color.secondary)
                        .frame(width: 32, height: 32)
                        .overlay(alignment: .bottomTrailing) {
                            if session.playbackActionPending {
                                ProgressView().controlSize(.mini)
                            } else if session.canControlPlayback {
                                Image(systemName: session.playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white).padding(3)
                                    .background(.brown, in: Circle())
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(!session.canControlPlayback)
                .help(playbackHelp)
                .accessibilityLabel(playbackHelp)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.device.name).font(.system(.body, weight: .semibold))
                    Text(session.displayModel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if session.ready {
                    Text("\(Int((session.volume * 100).rounded()))%")
                        .font(.system(.body, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if session.failed {
                    Button("Retry") { session.connect() }.buttonStyle(.borderless)
                } else {
                    ProgressView().controlSize(.small)
                }
            }

            if let title = session.playback.title {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: session.playback.isPlaying ? "waveform" : "music.note")
                        .foregroundStyle(session.playback.isPlaying ? Color.brown : Color.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        if !session.playback.label.isEmpty {
                            Text(session.playback.label.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(session.playback.isPlaying ? Color.brown : Color.secondary)
                        }
                        Text(title).font(.callout.weight(.medium)).lineLimit(2)
                        if let detail = session.playback.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 10) {
                Button { session.toggleMute() } label: {
                    Image(systemName: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 24)
                }
                .buttonStyle(.borderless)
                .help(session.muted ? "Unmute" : "Mute")
                .accessibilityLabel("\(session.muted ? "Unmute" : "Mute") \(session.device.name)")
                Slider(value: Binding(get: { session.volume }, set: { session.setVolume($0) }),
                       in: 0...1, onEditingChanged: session.setEditing)
                    .tint(.brown)
                    .accessibilityLabel("Volume for \(session.device.name)")
                    .accessibilityValue("\(Int((session.volume * 100).rounded())) percent")
            }.disabled(!session.ready)

            if !session.ready || session.muted {
                Text(session.muted && session.ready ? "Muted" : session.message)
                    .font(.caption).foregroundStyle(session.failed ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = session.playbackControlError {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(session.playback.isPlaying ? Color.brown.opacity(0.10) : Color.secondary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(session.playback.isPlaying ? Color.brown.opacity(0.45) : .clear, lineWidth: 1)
        }
    }

    private var playbackHelp: String {
        if session.playbackActionPending { return "Waiting for \(session.device.name)…" }
        guard session.canControlPlayback else { return "No controllable playback on \(session.device.name)" }
        return "\(session.playback.isPlaying ? "Pause" : "Resume") \(session.device.name)"
    }
}
