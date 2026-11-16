import AppKit
import MissionControlPlusCore
import os

/// Coordinates AX polling, window/Space resolution, and immediate overlay updates.
final class Engine {
    enum State: String { case inactive, idle, settling, showing }

    static let idleInterval: TimeInterval = 0.06
    static let openInterval: TimeInterval = 0.06
    static let noPermissionInterval: TimeInterval = 1.0
    static let renderThrottle: TimeInterval = 0.12

    private let log = Logger(subsystem: "com.robbieperlstein.MissionControlPlus", category: "engine")
    private let queue = DispatchQueue(label: "com.robbieperlstein.MissionControlPlus.collector", qos: .userInitiated)
    private let reader = MissionControlReader()
    private let resolver: WindowResolver
    private let sessions: SessionCounter
    private let overlay: OverlayController
    let diagnostics = Diagnostics()

    // Worker-queue isolated state
    private var enabled = false
    private var generation = 0
    private var renderedSnapshot: MissionControlSnapshot?
    private var lastRender = Date.distantPast
    private var wasOpen = false
    private var currentSession: SessionToken
    private var lastTrusted: Bool?
    private var config: FeatureConfig

    private(set) var state: State = .inactive {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((State) -> Void)?
    var onDiagnosticWritten: ((URL?) -> Void)?
    var onPermissionChange: ((Bool) -> Void)?

    init(sessions: SessionCounter, overlay: OverlayController, initialConfig: FeatureConfig = FeatureConfig()) {
        self.sessions = sessions
        self.overlay = overlay
        self.config = initialConfig
        self.currentSession = sessions.current
        self.resolver = WindowResolver(excludedPIDs: [ProcessInfo.processInfo.processIdentifier])
    }

    func updateConfig(_ newConfig: FeatureConfig) {
        queue.async {
            self.config = newConfig
            self.renderedSnapshot = nil
            self.lastRender = .distantPast
            if newConfig.shouldRunEngine || self.diagnostics.isArmed {
                self.startOnQueue()
            } else {
                self.stopOnQueue()
            }
        }
    }

    func armDiagnostics() {
        queue.async {
            self.diagnostics.arm()
            self.startOnQueue()
        }
    }

    func start() {
        queue.async { self.startOnQueue() }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    // MARK: - Worker Queue

    private func startOnQueue() {
        guard !enabled else { return }
        enabled = true
        generation += 1
        tick(generation: generation)
    }

    private func stopOnQueue() {
        enabled = false
        generation += 1
        endSessionIfOpen()
        setState(.inactive)
    }

    private func setState(_ newState: State) {
        DispatchQueue.main.async {
            if self.state != newState { self.state = newState }
        }
    }

    private func schedule(after interval: TimeInterval, generation: Int) {
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.tick(generation: generation)
        }
    }

    private func endSessionIfOpen() {
        if wasOpen || renderedSnapshot != nil {
            wasOpen = false
            renderedSnapshot = nil
            lastRender = .distantPast
            sessions.advance()
            resolver.invalidateSessionCaches()
            DispatchQueue.main.async { self.overlay.hide() }
        }
    }

    private func tick(generation: Int) {
        guard enabled, generation == self.generation else { return }

        let trusted = AX.isTrusted()
        if lastTrusted != trusted {
            lastTrusted = trusted
            DispatchQueue.main.async { self.onPermissionChange?(trusted) }
        }
        guard trusted else {
            endSessionIfOpen()
            setState(.inactive)
            schedule(after: Self.noPermissionInterval, generation: generation)
            return
        }

        let groups = reader.missionControlGroups()
        if groups.isEmpty {
            if wasOpen { log.debug("mission control closed") }
            endSessionIfOpen()
            setState(.idle)
            if diagnostics.isArmed, diagnostics.armedSeconds > Diagnostics.notFoundTimeout {
                diagnostics.disarm()
                let url = diagnostics.writeNotFound(reader: reader)
                DispatchQueue.main.async { self.onDiagnosticWritten?(url) }
                if !config.shouldRunEngine { stopOnQueue(); return }
            }
            schedule(after: Self.idleInterval, generation: generation)
            return
        }

        if !wasOpen {
            wasOpen = true
            currentSession = sessions.advance()
            resolver.invalidateSessionCaches()
            log.debug("mission control opened")
        }

        let wantWindows = config.effectiveShowWindowIcons
        let wantSpaces = config.effectiveReplaceSpaceNames
        let shouldProbeAll = diagnostics.isArmed
        let snapshot = reader.snapshot(
            in: groups,
            collectThumbnails: wantWindows || shouldProbeAll,
            collectSpaces: wantSpaces || shouldProbeAll
        )

        if snapshot.isEmpty {
            if renderedSnapshot != nil {
                renderedSnapshot = nil
                DispatchQueue.main.async { self.overlay.hide() }
            }
            if diagnostics.isArmed {
                diagnostics.disarm()
                let url = diagnostics.write(reader: reader, groups: groups, snapshot: snapshot, outcome: nil, windows: [])
                DispatchQueue.main.async { self.onDiagnosticWritten?(url) }
                if !config.shouldRunEngine { stopOnQueue(); return }
            }
            setState(.settling)
            schedule(after: Self.openInterval, generation: generation)
            return
        }

        let changed = renderedSnapshot.map { !LayoutStability.isStable($0, snapshot) } ?? true
        if changed, Date().timeIntervalSince(lastRender) >= Self.renderThrottle {
            render(snapshot: snapshot, groups: groups, resolveWindows: wantWindows, resolveSpaces: wantSpaces)
        }
        schedule(after: Self.openInterval, generation: generation)
    }

    private func render(
        snapshot: MissionControlSnapshot,
        groups: [AXUIElement],
        resolveWindows: Bool,
        resolveSpaces: Bool
    ) {
        let session = currentSession
        let outcome = resolver.resolve(
            snapshot: snapshot,
            hostPIDs: reader.hostPIDs,
            resolveWindows: resolveWindows,
            resolveSpaces: resolveSpaces
        )
        let st = outcome.stats
        log.info("resolved thumbs=\(st.thumbnailCount) spaces=\(st.spaceCount) resolvedSpaces=\(st.resolvedSpaceCount) elapsedMs=\(Int(st.elapsed * 1000))")

        renderedSnapshot = snapshot
        lastRender = Date()

        let winOverlays = outcome.windowOverlays
        let spaceOverlays = outcome.spaceOverlays
        let allSpaces = snapshot.spaces

        DispatchQueue.main.async {
            self.overlay.show(
                windowOverlays: winOverlays,
                spaceOverlays: spaceOverlays,
                allSpaces: allSpaces,
                session: session
            )
            self.state = .showing
        }

        if diagnostics.isArmed {
            diagnostics.disarm()
            let url = diagnostics.write(
                reader: reader,
                groups: groups,
                snapshot: snapshot,
                outcome: outcome,
                windows: resolver.lastWindows
            )
            DispatchQueue.main.async { self.onDiagnosticWritten?(url) }
            if !config.shouldRunEngine { stopOnQueue() }
        }
    }
}
