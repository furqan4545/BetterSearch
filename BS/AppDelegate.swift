import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var searchPanel: SearchPanel!
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        searchPanel = SearchPanel()
        setupStatusBar()
        setupHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "BS Search")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Search", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit BS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupHotkey() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .shift] && event.keyCode == 49 {
                DispatchQueue.main.async {
                    self?.togglePanel()
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .shift] && event.keyCode == 49 {
                self?.togglePanel()
                return nil
            }
            return event
        }
    }

    @objc private func togglePanel() {
        searchPanel.toggle()
    }
}
