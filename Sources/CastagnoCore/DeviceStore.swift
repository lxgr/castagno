import Combine
import Foundation
import OpenCastSwift

enum VolumeValue {
    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
    static func percent(_ value: Double) -> Int {
        Int((clamp(value) * 100).rounded())
    }
}

enum GroupVisibility {
    // Bonjour and multizone status can represent the same UUID differently.
    static func canonicalID(_ id: String) -> String {
        id.lowercased().replacingOccurrences(of: "-", with: "")
    }

    static func visibleIDs(devices: [CastDevice], membersByGroup: [String: Set<String>]) -> Set<String> {
        let groupIDs = Set(devices.filter { $0.isGroup }.map(\.id))
        let memberIDs = Set(groupIDs.flatMap { membersByGroup[$0] ?? [] }
            .filter { !$0.isEmpty }.map(canonicalID))
        return Set(devices.filter {
            groupIDs.contains($0.id) || !memberIDs.contains(canonicalID($0.id))
        }.map(\.id))
    }

    static func memberships(devices: [CastDevice], reportedMembers: [String: Set<String>],
                            groupsByDevice: [String: Set<String>]) -> [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: devices.filter { $0.isGroup }.map { group in
            let groupID = canonicalID(group.id)
            var members = Set((reportedMembers[group.id] ?? []).map(canonicalID)
                .filter { !$0.isEmpty && $0 != groupID })
            for device in devices where !device.isGroup {
                if (groupsByDevice[device.id] ?? []).contains(where: { canonicalID($0) == groupID }) {
                    members.insert(canonicalID(device.id))
                }
            }
            return (group.id, members)
        })
    }
}

/// OpenCastSwift streams and Bonjour discovery are confined to the main run loop.
public final class DeviceStore: ObservableObject {
    public let isDemo: Bool
    @Published public private(set) var devices: [DeviceSession] = []
    @Published public private(set) var discoveryError: String?
    @Published public private(set) var discoveryProgress = DiscoveryProgress()
    private let scanner: CastDeviceScanner
    private let settleInterval: TimeInterval
    private let makeSession: (CastDevice) -> DeviceSession
    private let interactionHoldInterval: TimeInterval
    private var heldDeviceID: String?
    private var heldDeviceIndex = 0
    private var releaseHold: DispatchWorkItem?
    private var settle: DispatchWorkItem?
    private var observer: NSObjectProtocol?
    private var sessions: [DeviceSession] = []

    public convenience init() {
        self.init(scanner: CastDeviceScanner(), startScanning: true)
    }

    /// A screenshot-friendly, interactive scene that never accesses the network.
    public static func demo() -> DeviceStore {
        let store = DeviceStore(scanner: CastDeviceScanner(), startScanning: false, demoMode: true)
        store.resetDemo()
        return store
    }

    init(scanner: CastDeviceScanner, startScanning: Bool, settleInterval: TimeInterval = 2,
         interactionHoldInterval: TimeInterval = 30, demoMode: Bool = false,
         makeSession: @escaping (CastDevice) -> DeviceSession = { DeviceSession(device: $0) }) {
        self.scanner = scanner
        self.isDemo = demoMode
        self.settleInterval = settleInterval
        self.makeSession = makeSession
        self.interactionHoldInterval = interactionHoldInterval
        observer = NotificationCenter.default.addObserver(
            forName: CastDeviceScanner.deviceListDidChange, object: scanner, queue: .main
        ) { [weak self] _ in self?.synchronize() }
        scanner.discoveryError = { [weak self] in
            self?.discoveryError = $0
            self?.settle?.cancel()
            self?.discoveryProgress.phase = .failed
        }
        scanner.progressDidChange = { [weak self] in self?.receiveDiscoveryProgress($0) }
        if startScanning && !isDemo { scanner.startScanning() }
    }

    func receiveDiscoveryProgress(_ progress: CastDiscoveryProgress) {
        settle?.cancel()
        discoveryProgress = DiscoveryProgress(
            phase: discoveryError != nil ? .failed : !progress.isScanning ? .stopped
                : progress.resolvingServices > 0 ? .resolving : .searching,
            foundServices: progress.foundServices, resolvingServices: progress.resolvingServices,
            failedServices: progress.failedServices, discoveredDevices: progress.discoveredDevices)
        guard progress.isScanning, progress.resolvingServices == 0, discoveryError == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.discoveryProgress.phase = .monitoring }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleInterval, execute: work)
    }

    public func rescan() {
        if isDemo { resetDemo(); return }
        discoveryError = nil
        scanner.reset()
        scanner.startScanning()
    }

    private func resetDemo() {
        releaseHold?.cancel()
        heldDeviceID = nil
        sessions.forEach { $0.stop() }
        sessions = DemoReceiver.scene.map { fixture in
            let session = DeviceSession(device: fixture.device, demo: fixture)
            session.playbackDidChange = { [weak self] in self?.updateVisibleDevices() }
            session.interactionDidOccur = { [weak self, weak session] in
                guard let session else { return }
                self?.holdPosition(of: session.id)
            }
            return session
        }
        discoveryProgress = DiscoveryProgress(phase: .monitoring, foundServices: sessions.count,
                                              discoveredDevices: sessions.count)
        updateVisibleDevices()
    }

    public func shutdown() {
        releaseHold?.cancel()
        settle?.cancel()
        scanner.stopScanning()
        sessions.forEach { $0.stop() }
    }

    public func session(id: String) -> DeviceSession? {
        sessions.first { GroupVisibility.canonicalID($0.id) == GroupVisibility.canonicalID(id) }
    }

    public func snapshot(includeGroupMembers: Bool = false) -> DiscoverySnapshot {
        let memberships = resolvedMemberships()
        return DiscoverySnapshot(devices: (includeGroupMembers ? sessions : devices).map {
            $0.snapshot(memberIDs: memberships[$0.id]?.sorted())
        },
                          discoveryError: discoveryError, discovery: discoveryProgress)
    }

    private func synchronize() {
        let discovered = scanner.devices
        let ids = Set(discovered.map(\.id))
        sessions.filter { !ids.contains($0.id) }.forEach { $0.stop() }
        sessions = discovered.map { device in
            if let existing = sessions.first(where: { $0.id == device.id }),
               existing.device.hostName == device.hostName,
               existing.device.ipAddress == device.ipAddress,
               existing.device.port == device.port {
                existing.device = device
                return existing
            }
            sessions.first(where: { $0.id == device.id })?.stop()
            let session = makeSession(device)
            session.groupMembersDidChange = { [weak self] in self?.updateVisibleDevices() }
            session.playbackDidChange = { [weak self] in self?.updateVisibleDevices() }
            session.interactionDidOccur = { [weak self, weak session] in
                guard let session else { return }
                self?.holdPosition(of: session.id)
            }
            return session
        }.sorted { $0.device.name.localizedStandardCompare($1.device.name) == .orderedAscending }
        updateVisibleDevices()
    }

    private func updateVisibleDevices() {
        let memberships = resolvedMemberships()
        let stereoPairs = Set(sessions.flatMap { $0.setupMembership.stereoPairIDs }.map(GroupVisibility.canonicalID))
        for session in sessions where !isDemo {
            let kind: ReceiverKind = !session.device.isGroup ? .device
                : stereoPairs.contains(GroupVisibility.canonicalID(session.id)) ? .stereoPair : .speakerGroup
            let model: String
            switch kind {
            case .device: model = session.device.modelName
            case .speakerGroup: model = "Speaker group"
            case .stereoPair:
                let members = memberships[session.id] ?? []
                let models = Set(sessions.filter { members.contains(GroupVisibility.canonicalID($0.id)) }
                    .map { $0.device.modelName })
                model = models.count == 1 ? "\(models.first!) · Stereo pair" : "Stereo pair"
            }
            if session.kind != kind { session.kind = kind }
            if session.displayModel != model { session.displayModel = model }
        }
        let visibleIDs = GroupVisibility.visibleIDs(devices: sessions.map(\.device), membersByGroup: memberships)
        var ordered = sessions.filter { visibleIDs.contains($0.id) }.sorted {
            DeviceOrdering.precedes(playing: $0.playback.isPlaying, name: $0.device.name, id: $0.id,
                                    otherPlaying: $1.playback.isPlaying, otherName: $1.device.name, otherID: $1.id)
        }
        if let id = heldDeviceID, let index = ordered.firstIndex(where: { $0.id == id }) {
            let held = ordered.remove(at: index)
            ordered.insert(held, at: min(heldDeviceIndex, ordered.count))
        } else if heldDeviceID != nil {
            releaseHold?.cancel()
            heldDeviceID = nil
        }
        devices = ordered
    }

    private func holdPosition(of id: String) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        heldDeviceID = id
        heldDeviceIndex = index
        releaseHold?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.heldDeviceID = nil
            self?.updateVisibleDevices()
        }
        releaseHold = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interactionHoldInterval, execute: work)
    }

    private func resolvedMemberships() -> [String: Set<String>] {
        GroupVisibility.memberships(devices: sessions.map(\.device),
            reportedMembers: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.groupMemberIDs) }),
            groupsByDevice: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.containingGroupIDs) }))
    }

    deinit {
        releaseHold?.cancel()
        settle?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

public final class DeviceSession: NSObject, ObservableObject, Identifiable, CastClientDelegate {
    private let demo: DemoReceiver?
    public var id: String { device.id }
    @Published public fileprivate(set) var device: CastDevice
    @Published public fileprivate(set) var kind: ReceiverKind
    @Published public fileprivate(set) var displayModel: String
    @Published public private(set) var volume: Double = 0
    @Published public private(set) var confirmedVolume: Double?
    public private(set) var statusRevision: UInt = 0
    @Published public private(set) var muted = false
    @Published public private(set) var ready = false
    @Published public private(set) var message = "Connecting…"
    @Published public private(set) var failed = false
    @Published public private(set) var connectionAttempts = 0
    @Published public private(set) var lastConnectionError: ConnectionFailure?
    @Published public private(set) var playbackActionPending = false
    @Published public private(set) var playbackControlError: String?
    public var canControlPlayback: Bool {
        if demo != nil { return active && ready && (playback.state == .playing || playback.state == .paused) }
        return ready && !playbackActionPending && mediaApp?.supportsMediaStatus == true
            && (mediaStatus?.mediaSessionId ?? 0) > 0
            && (playback.state == .playing || playback.state == .paused)
    }
    @Published public private(set) var playback = PlaybackInfo() {
        didSet {
            if oldValue.isPlaying != playback.isPlaying { playbackDidChange?() }
        }
    }
    var playbackDidChange: (() -> Void)?
    var interactionDidOccur: (() -> Void)?
    private var mediaApp: CastApp?
    private var mediaStatus: CastMediaStatus?
    private var playbackTarget: CastMediaPlayerState?
    private var playbackSessionID: Int?
    private var playbackTimeout: DispatchWorkItem?
    private let sendPlayback: (CastClient, Bool) -> Void
    private let playbackConfirmationTimeout: TimeInterval
    private var client: CastClient?
    private var timeout: DispatchWorkItem?
    private var pendingVolume: DispatchWorkItem?
    private var refreshTimer: Timer?
    private var editing = false
    private var active = true
    private var reconnect: DispatchWorkItem?
    private var consecutiveFailures = 0
    private let startConnection: (CastClient) -> Void
    private let retryDelay: (Int) -> TimeInterval
    private var membershipProbe: GroupMembershipProbe?
    private var membershipTimer: Timer?
    var containingGroupIDs: Set<String> { setupMembership.groupIDs }
    private(set) var setupMembership = ReceiverGroupMembership() {
        didSet { if oldValue != setupMembership { groupMembersDidChange?() } }
    }
    private(set) var groupMemberIDs: Set<String> = [] {
        didSet {
            if oldValue != groupMemberIDs { groupMembersDidChange?() }
        }
    }
    var groupMembersDidChange: (() -> Void)?

    init(device: CastDevice,
         startConnection: @escaping (CastClient) -> Void = { $0.connect() },
         retryDelay: @escaping (Int) -> TimeInterval = { min(30, pow(2, Double(min($0, 5)))) },
         sendPlayback: @escaping (CastClient, Bool) -> Void = { client, playing in
             if playing { client.play() } else { client.pause() }
         }, playbackConfirmationTimeout: TimeInterval = 5, demo: DemoReceiver? = nil) {
        self.demo = demo
        self.device = device
        self.kind = device.isGroup ? .speakerGroup : .device
        self.displayModel = device.isGroup ? "Speaker group" : device.modelName
        self.startConnection = startConnection
        self.retryDelay = retryDelay
        self.sendPlayback = sendPlayback
        self.playbackConfirmationTimeout = playbackConfirmationTimeout
        super.init()
        if let demo {
            kind = demo.kind
            displayModel = demo.model
            volume = demo.volume
            confirmedVolume = demo.volume
            ready = true
            message = "Demo device"
            var info = PlaybackInfo()
            info.state = demo.playing ? .playing : .paused
            info.title = demo.title
            info.detail = "\(demo.artist) · Spotify"
            playback = info
            return
        }
        if !device.isGroup, !device.ipAddress.isEmpty {
            membershipProbe = GroupMembershipProbe(address: device.ipAddress) { [weak self] membership in
                self?.updateMembership(membership)
            }
            membershipProbe?.refresh()
            let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
                self?.membershipProbe?.refresh()
            }
            membershipTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        connect()
    }

    public func connect() {
        guard demo == nil else { return }
        interactionDidOccur?()
        consecutiveFailures = 0
        beginConnection()
    }

    func updateMembership(_ membership: ReceiverGroupMembership) {
        guard active else { return }
        setupMembership = membership
    }

    private func beginConnection() {
        stopConnection()
        connectionAttempts += 1
        active = true
        failed = false
        message = "Connecting…"
        let client = CastClient(device: device)
        self.client = client
        client.delegate = self
        client.multizoneStatusDidChange = { [weak self, weak client] status in
            guard let self, let client, self.client === client, self.active else { return }
            self.groupMemberIDs = Set(status.devices.map(\.id).filter { !$0.isEmpty })
        }
        startConnection(client)
        let timeout = DispatchWorkItem { [weak self, weak client] in
            guard let self, let client, self.client === client, !self.ready else { return }
            self.fail("Receiver did not respond.")
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
    }

    public func setVolume(_ value: Double) {
        guard ready else { return }
        interactionDidOccur?()
        volume = VolumeValue.clamp(value)
        if demo != nil {
            confirmedVolume = volume
            statusRevision += 1
            return
        }
        pendingVolume?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushVolume() }
        pendingVolume = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    public func setEditing(_ value: Bool) {
        editing = value
        if !value { flushVolume() }
    }

    private func flushVolume() {
        guard pendingVolume != nil else { return }
        pendingVolume?.cancel()
        pendingVolume = nil
        guard ready else { return }
        client?.setVolume(Float(volume))
        client?.requestStatus()
    }

    public func toggleMute() { setMuted(!muted) }

    public func setMuted(_ value: Bool) {
        guard ready else { return }
        interactionDidOccur?()
        if demo != nil { muted = value; statusRevision += 1; return }
        client?.setMuted(value)
        // Display receiver-confirmed mute state.
        client?.requestStatus()
    }

    @discardableResult
    public func togglePlayback() -> Bool { setPlaying(!playback.isPlaying) }

    /// Pause/resume existing media only; never launch an app or load a new track.
    @discardableResult
    public func setPlaying(_ playing: Bool) -> Bool {
        if demo != nil {
            guard canControlPlayback else { return false }
            interactionDidOccur?()
            var info = playback
            info.state = playing ? .playing : .paused
            playback = info
            return true
        }
        guard canControlPlayback, let client, let app = mediaApp else { return false }
        interactionDidOccur?()
        let target: CastMediaPlayerState = playing ? .playing : .paused
        playbackControlError = nil
        guard playback.state != target else { return true }
        playbackTarget = target
        playbackSessionID = mediaStatus?.mediaSessionId
        playbackActionPending = true
        let timeout = DispatchWorkItem { [weak self] in
            self?.finishPlayback(error: "Receiver did not confirm playback. Try again.")
        }
        playbackTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + playbackConfirmationTimeout, execute: timeout)
        sendPlayback(client, playing)
        client.requestMediaStatus(for: app)
        return true
    }

    private func finishPlayback(error: String? = nil) {
        playbackTimeout?.cancel()
        playbackTimeout = nil
        playbackTarget = nil
        playbackSessionID = nil
        playbackActionPending = false
        playbackControlError = error
    }

    public func stop() {
        active = false
        membershipProbe?.stop()
        membershipTimer?.invalidate()
        membershipTimer = nil
        setupMembership = ReceiverGroupMembership()
        stopConnection()
    }

    private func stopConnection() {
        finishPlayback()
        reconnect?.cancel()
        reconnect = nil
        ready = false
        confirmedVolume = nil
        editing = false
        timeout?.cancel()
        timeout = nil
        pendingVolume?.cancel()
        pendingVolume = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        client?.delegate = nil
        client?.multizoneStatusDidChange = nil
        client?.disconnect()
        client = nil
        groupMemberIDs = []
        mediaApp = nil
        mediaStatus = nil
        playback = PlaybackInfo()
    }

    private func fail(_ text: String, error: Error? = nil) {
        stopConnection()
        failed = true
        guard active else { return }
        let failure = ConnectionFailure(error: error ?? NSError(domain: "CastagnoConnection", code: 0,
            userInfo: [NSLocalizedDescriptionKey: text]))
        lastConnectionError = failure
        let address = device.ipAddress.isEmpty ? device.hostName : device.ipAddress
        let diagnostic = "Castagno: \(device.name) \(address):\(device.port), attempt \(connectionAttempts): \(failure.domain) \(failure.code): \(failure.description)\n"
        FileHandle.standardError.write(Data(diagnostic.utf8))
        consecutiveFailures += 1
        let delay = retryDelay(consecutiveFailures)
        message = "\(failure.guidance) Reconnecting in \(Int(delay.rounded(.up)))s…"
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.active else { return }
            self.beginConnection()
        }
        reconnect = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func castClient(_ client: CastClient, didConnectTo device: CastDevice) {
        guard self.client === client, active else { return }
        message = "Reading volume…"
        client.requestStatus()
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.client?.requestStatus()
            if let self, let app = self.mediaApp, app.supportsMediaStatus {
                self.client?.requestMediaStatus(for: app)
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func castClient(_ client: CastClient, deviceStatusDidChange status: CastStatus) {
        guard self.client === client, active else { return }
        timeout?.cancel()
        timeout = nil
        ready = true
        consecutiveFailures = 0
        failed = false
        message = "Connected"
        if !editing && pendingVolume == nil { volume = VolumeValue.clamp(status.volume) }
        confirmedVolume = VolumeValue.clamp(status.volume)
        statusRevision += 1
        muted = status.muted
        let app = status.apps.first { !$0.isIdleScreen && !$0.transportId.isEmpty }
        let changed = mediaApp?.sessionId != app?.sessionId || mediaApp?.transportId != app?.transportId
        if changed {
            if playbackActionPending { finishPlayback(error: "Playback session changed before confirmation.") }
            mediaStatus = nil
        }
        mediaApp = app
        playback = PlaybackInfo(app: app, media: mediaStatus)
        if changed { client.observeMedia(in: app) }
    }

    public func castClient(_ client: CastClient, mediaStatusDidChange status: CastMediaStatus) {
        guard self.client === client, active, mediaApp != nil else { return }
        if let sourceId = status.sourceId, sourceId != mediaApp?.transportId { return }
        mediaStatus = status
        playback = PlaybackInfo(app: mediaApp, media: status)
        if playbackActionPending {
            if status.mediaSessionId != playbackSessionID {
                finishPlayback(error: "Playback session changed before confirmation.")
            } else if status.playerState == playbackTarget {
                finishPlayback()
            }
        }
    }

    public func castClient(_ client: CastClient, didDisconnectFrom device: CastDevice) {
        guard self.client === client, active else { return }
        fail("Connection lost.")
    }

    public func castClient(_ client: CastClient, connectionTo device: CastDevice, didFailWith error: Error?) {
        guard self.client === client, active else { return }
        fail(error?.localizedDescription ?? "Unable to connect to this receiver.", error: error)
    }
}
