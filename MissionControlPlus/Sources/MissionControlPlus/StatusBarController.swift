import AppKit
import Combine
import SwiftUI

/// Menu bar icon presenting an interactive SwiftUI popover with toggle switches.
@MainActor
final class StatusBarController: NSObject {
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverControlsView(model: model))

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            updateIcon(active: model.statusIsActive)
        }

        model.onClosePopover = { [weak self] in
            self?.popover.performClose(nil)
        }

        model.$isMasterEnabled
            .combineLatest(model.$showWindowIcons, model.$replaceSpaceNames, model.$isTrusted)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                guard let self else { return }
                self.updateIcon(active: self.model.statusIsActive)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(active: Bool) {
        guard let button = item.button else { return }
        let symbol = active ? "rectangle.3.group.fill" : "rectangle.3.group"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "MissionControlPlus")
        img?.isTemplate = true
        button.image = img
        button.appearsDisabled = !active
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.refreshAccessibilityStatus()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
