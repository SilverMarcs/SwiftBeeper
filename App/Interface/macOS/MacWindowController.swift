#if os(macOS)
import AppKit

@MainActor
final class MacWindowController: NSWindowController {
    private let context: AppContext
    private let observation = ObservationLifetime()
    private var settingsWindow: NSWindow?

    init(context: AppContext) {
        self.context = context
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Relay"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 900, height: 600)
        window.contentViewController = MacRootController(context: context)
        window.setFrameAutosaveName("RelayMainWindow")
        window.center()
        super.init(window: window)
        installMenus()
        observation.track { [weak self] in self?.renderRoot() }
    }

    required init?(coder: NSCoder) { nil }

    private func renderRoot() {
        guard let window else { return }
        if context.state == .ready {
            if !(window.contentViewController is MacConversationsController) { window.contentViewController = MacConversationsController(context: context) }
        } else {
            window.title = "Relay"
            if !(window.contentViewController is MacRootController) { window.contentViewController = MacRootController(context: context) }
        }
    }

    func showSettings() {
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); return }
        let hosting = MacSettingsController(context: context)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 500))
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func findChats() { (window?.contentViewController as? MacConversationsController)?.focusSearch() }

    private func installMenus() {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "About Relay", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Relay", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Relay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = app; main.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        edit.addItem(.separator())
        edit.addItem(withTitle: "Find Conversations…", action: #selector(findChats), keyEquivalent: "f").target = self
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem(); windowItem.submenu = window; main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }
}
#endif
