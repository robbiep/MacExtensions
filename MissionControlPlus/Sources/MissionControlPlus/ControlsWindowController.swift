import AppKit
import SwiftUI

/// Hosts the main SwiftUI controls window, switching between `.regular` (when visible)
/// and `.accessory` (when closed, so the app runs quietly in the menu bar without Dock clutter).
@MainActor
final class ControlsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        let win = ensureWindow()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func ensureWindow() -> NSWindow {
        if let existing = window { return existing }
        let hosting = NSHostingController(rootView: ControlsWindowView(model: model))
        let win = NSWindow(contentViewController: hosting)
        win.title = "MissionControlPlus"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.moveToActiveSpace]
        win.delegate = self
        win.center()
        self.window = win
        return win
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}
