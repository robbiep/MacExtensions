import AppKit
import Combine
import MissionControlPlusCore
import ServiceManagement
import SwiftUI

/// Single source of truth for master switch, individual feature toggles, permissions, and app actions.
@MainActor
final class AppModel: ObservableObject {
    private enum DefaultsKey {
        static let masterEnabled = "isMasterEnabled"
        static let showWindowIcons = "showWindowIcons"
        static let replaceSpaceNames = "replaceSpaceNames"
        static let showWindowTitles = "showWindowTitles"
        static let iconAnchor = "iconAnchor"
        static let openWindowOnLaunch = "openWindowOnLaunch"
    }

    @Published var isMasterEnabled: Bool {
        didSet { persistAndSync() }
    }
    @Published var showWindowIcons: Bool {
        didSet { persistAndSync() }
    }
    @Published var replaceSpaceNames: Bool {
        didSet { persistAndSync() }
    }
    @Published var showWindowTitles: Bool {
        didSet { persistAndSync() }
    }
    @Published var iconAnchor: OverlayAnchor {
        didSet { persistAndSync() }
    }
    @Published var openWindowOnLaunch: Bool {
        didSet { UserDefaults.standard.set(openWindowOnLaunch, forKey: DefaultsKey.openWindowOnLaunch) }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var isTrusted: Bool
    @Published private(set) var engineState: Engine.State = .inactive
    @Published var lastStatsSummary: String?
    @Published var diagnosticNote: String?

    var featureConfig: FeatureConfig {
        FeatureConfig(
            isMasterEnabled: isMasterEnabled,
            showWindowIcons: showWindowIcons,
            replaceSpaceNames: replaceSpaceNames,
            showWindowTitles: showWindowTitles,
            anchor: iconAnchor
        )
    }

    var statusLabel: String {
        if !isTrusted { return "Permission Required" }
        if !isMasterEnabled { return "Turned Off" }
        if !featureConfig.shouldRunEngine { return "On (All Features Off)" }
        switch engineState {
        case .inactive: return "Starting…"
        case .idle: return "Ready"
        case .settling: return "Reading Layout…"
        case .showing: return "Active in Mission Control"
        }
    }

    var statusIsActive: Bool {
        isTrusted && isMasterEnabled && featureConfig.shouldRunEngine
    }

    private let overlay: OverlayController
    private let engine: Engine
    private var trustPollTimer: Timer?
    var onOpenControlsWindow: (() -> Void)?
    var onClosePopover: (() -> Void)?

    init(overlay: OverlayController, engine: Engine) {
        self.overlay = overlay
        self.engine = engine

        let d = UserDefaults.standard
        Self.registerDefaults(in: d)

        self.isMasterEnabled = d.bool(forKey: DefaultsKey.masterEnabled)
        self.showWindowIcons = d.bool(forKey: DefaultsKey.showWindowIcons)
        self.replaceSpaceNames = d.bool(forKey: DefaultsKey.replaceSpaceNames)
        self.showWindowTitles = d.bool(forKey: DefaultsKey.showWindowTitles)
        self.iconAnchor = OverlayAnchor(rawValue: d.string(forKey: DefaultsKey.iconAnchor) ?? "") ?? .default
        self.openWindowOnLaunch = d.bool(forKey: DefaultsKey.openWindowOnLaunch)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.isTrusted = AX.isTrusted()

        wireEngineCallbacks()
        syncConfig()
        startTrustPollingIfNeeded()
    }

    private static func registerDefaults(in d: UserDefaults) {
        d.register(defaults: [
            DefaultsKey.masterEnabled: true,
            DefaultsKey.showWindowIcons: true,
            DefaultsKey.replaceSpaceNames: true,
            DefaultsKey.showWindowTitles: false,
            DefaultsKey.iconAnchor: OverlayAnchor.default.rawValue,
            DefaultsKey.openWindowOnLaunch: true,
        ])
    }

    private func wireEngineCallbacks() {
        engine.onStateChange = { [weak self] newState in
            Task { @MainActor [weak self] in
                self?.engineState = newState
            }
        }
        engine.onStatsUpdate = { [weak self] st in
            Task { @MainActor [weak self] in
                self?.lastStatsSummary = "Last run: \(st.thumbnailCount) windows, \(st.spaceCount) spaces (\(st.resolvedSpaceCount) renamed)"
            }
        }
        engine.onPermissionChange = { [weak self] trusted in
            Task { @MainActor [weak self] in
                self?.handleTrustChange(trusted)
            }
        }
        engine.onDiagnosticWritten = { [weak self] url in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.diagnosticNote = url.map { "Saved \($0.lastPathComponent)" } ?? "Diagnostics failed"
                if let url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }

    private func persistAndSync() {
        let d = UserDefaults.standard
        d.set(isMasterEnabled, forKey: DefaultsKey.masterEnabled)
        d.set(showWindowIcons, forKey: DefaultsKey.showWindowIcons)
        d.set(replaceSpaceNames, forKey: DefaultsKey.replaceSpaceNames)
        d.set(showWindowTitles, forKey: DefaultsKey.showWindowTitles)
        d.set(iconAnchor.rawValue, forKey: DefaultsKey.iconAnchor)
        syncConfig()
    }

    private func syncConfig() {
        let cfg = featureConfig
        overlay.config = cfg
        engine.updateConfig(cfg)
    }

    func refreshAccessibilityStatus() {
        handleTrustChange(AX.isTrusted())
    }

    func requestAccessibilityPrompt() {
        AX.promptForTrust()
        refreshAccessibilityStatus()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func resetStaleAccessibilityEntry() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleID]
        try? task.run()
        task.waitUntilExit()
        diagnosticNote = "Permission entry reset — toggle MissionControlPlus ON in Device Control and Data Access."
        AX.promptForTrust()
        openAccessibilitySettings()
        refreshAccessibilityStatus()
    }

    func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Launch at Login Unavailable"
            alert.informativeText = "Move MissionControlPlus.app to /Applications or add it under System Settings → General → Login Items.\n\n(\(error.localizedDescription))"
            alert.runModal()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func armDiagnostics() {
        diagnosticNote = "Armed — open Mission Control once"
        engine.armDiagnostics()
    }

    func openLogsFolder() {
        let dir = Diagnostics.logDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func openControlsWindow() {
        onClosePopover?()
        onOpenControlsWindow?()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func handleTrustChange(_ trusted: Bool) {
        if isTrusted != trusted {
            isTrusted = trusted
            if trusted {
                syncConfig()
            }
        }
        if trusted {
            trustPollTimer?.invalidate()
            trustPollTimer = nil
        } else {
            startTrustPollingIfNeeded()
        }
    }

    private func startTrustPollingIfNeeded() {
        guard !isTrusted, trustPollTimer == nil else { return }
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAccessibilityStatus()
            }
        }
    }
}
