import AppKit
import MissionControlPlusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessions = SessionCounter()
    private var overlay: OverlayController!
    private var engine: Engine!
    private var model: AppModel!
    private var statusBar: StatusBarController!
    private var windowController: ControlsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        overlay = OverlayController(sessions: sessions)
        engine = Engine(sessions: sessions, overlay: overlay)
        model = AppModel(overlay: overlay, engine: engine)
        windowController = ControlsWindowController(model: model)
        statusBar = StatusBarController(model: model)

        model.onOpenControlsWindow = { [weak self] in
            self?.windowController.showWindow()
        }

        if CommandLine.arguments.contains("--probe") {
            model.armDiagnostics()
        }

        if model.openWindowOnLaunch {
            windowController.showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        overlay.tearDown()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MissionControlPlus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
