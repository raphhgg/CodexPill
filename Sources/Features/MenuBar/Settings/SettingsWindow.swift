import AppKit
import SwiftUI

/// rusage's own Settings window, not SwiftUI's `Settings` scene, which an accessory app can't reliably open or bring
/// forward. Toolbar panes, a title that follows the pane and a size that follows its content, with minimize and zoom
/// off and the last pane restored, as the HIG asks of a settings window.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let settings: SettingsModel
    private let state: SettingsWindowState
    private unowned let actions: any SettingsActions
    private let bringsAppForward: Bool
    private(set) var window: NSWindow?
    /// The pane shown last, restored the next time the window opens.
    private var selectedPane = 0

    /// Tests pass `bringsAppForward: false`, so the test host keeps its activation policy and stays behind.
    init(settings: SettingsModel, state: SettingsWindowState, actions: any SettingsActions, bringsAppForward: Bool = true) {
        self.settings = settings
        self.state = state
        self.actions = actions
        self.bringsAppForward = bringsAppForward
    }

    var isShown: Bool { window != nil }

    /// An accessory app's window opens behind the active app, so the app turns regular, with a Dock icon, while the
    /// window shows, and comes forward with `ignoringOtherApps`.
    func show() {
        let window = window ?? makeWindow()
        self.window = window
        guard bringsAppForward else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = Self.mainMenu(settingsTarget: self)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    var paneTitles: [String] {
        (window?.contentViewController as? NSTabViewController)?.tabViewItems.map(\.label) ?? []
    }

    /// A new window each time, so its SwiftUI content exists only while it shows.
    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for pane in SettingsPane.all(settings: settings, state: state, actions: actions) {
            let content = NSHostingController(rootView: pane.view)
            content.sizingOptions = [.preferredContentSize]
            content.title = pane.title
            let item = NSTabViewItem(viewController: content)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = min(selectedPane, tabs.tabViewItems.count - 1)
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    @objc
    private func showFromMainMenu() {
        show()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        actions.settingsWindowDidBecomeKey()
    }

    /// Drops the window and its SwiftUI content, so nothing observes the settings while it is closed.
    func windowWillClose(_ notification: Notification) {
        selectedPane = (window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex ?? 0
        window?.contentViewController = nil
        window = nil
        if bringsAppForward { NSApp.setActivationPolicy(.accessory) }
    }

    /// Never shown, since rusage is in the menu bar, but it answers ⌘, ⌘W ⌘Q and text editing while the window is key.
    private static func mainMenu(settingsTarget: SettingsWindow) -> NSMenu {
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showFromMainMenu), keyEquivalent: ",")
        settingsItem.target = settingsTarget
        let app = menu("rusage", [
            settingsItem,
            .separator(),
            NSMenuItem(title: "Quit rusage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ])
        let edit = menu("Edit", [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        let window = menu("Window", [
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ])
        return menu("", [app, edit, window].map { submenu in
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            return item
        })
    }

    private static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        return menu
    }
}
