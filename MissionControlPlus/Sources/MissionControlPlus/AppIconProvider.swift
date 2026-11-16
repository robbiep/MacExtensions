import AppKit

/// Shared app metadata & icon cache resolved by PID or bundle identifier.
final class AppIconProvider {
    private var iconByPID: [pid_t: NSImage] = [:]
    private var iconByBundleID: [String: NSImage] = [:]

    func icon(for pid: pid_t?, bundleID: String?) -> NSImage? {
        if let pid {
            if let cached = iconByPID[pid] { return cached }
            if let img = NSRunningApplication(processIdentifier: pid)?.icon {
                iconByPID[pid] = img
                return img
            }
        }
        if let bundleID {
            if let cached = iconByBundleID[bundleID] { return cached }
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
               let img = app.icon {
                iconByBundleID[bundleID] = img
                return img
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let img = NSWorkspace.shared.icon(forFile: url.path)
                iconByBundleID[bundleID] = img
                return img
            }
        }
        return nil
    }

    func invalidateSessionCaches() {
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        iconByPID = iconByPID.filter { running.contains($0.key) }
    }
}

/// Resolves concise app display names (`CFBundleName` e.g. `"Chrome"`, `"Code"`, `"Live"`, `"Slack"`).
enum AppNameHelper {
    static func shortName(for app: NSRunningApplication) -> String {
        if let bundleURL = app.bundleURL,
           let bundle = Bundle(url: bundleURL),
           let cfName = (bundle.infoDictionary?["CFBundleName"] as? String)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !cfName.isEmpty {
            return cfName
        }
        if let localized = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localized.isEmpty {
            return localized
        }
        if let url = app.bundleURL {
            return url.deletingPathExtension().lastPathComponent
        }
        return app.bundleIdentifier ?? "App"
    }

    static func localizedName(for app: NSRunningApplication) -> String {
        app.localizedName ?? shortName(for: app)
    }
}
