import AppKit
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "app")

class AppDelegate: NSObject, NSApplicationDelegate {
    private var searchPanel: SearchPanel!
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.warning("App launched")

        // Hide the default SwiftUI window
        for window in NSApp.windows {
            window.orderOut(nil)
        }

        // Start building in-memory file index immediately
        FileIndexer.shared.buildIndex()

        searchPanel = SearchPanel()
        setupStatusBar()
        setupHotkey()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Hide the SwiftUI window again (it can appear late)
            for window in NSApp.windows where window !== self.searchPanel {
                window.orderOut(nil)
            }
            self.searchPanel.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        searchPanel.show()
        return false
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
        menu.addItem(NSMenuItem(title: "Search", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit BS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupHotkey() {
        // Option+Space to toggle search panel
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.option] && event.keyCode == 49 {
                logger.warning("Global hotkey triggered")
                DispatchQueue.main.async {
                    self?.searchPanel.toggle()
                }
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.option] && event.keyCode == 49 {
                logger.warning("Local hotkey triggered")
                self?.searchPanel.toggle()
                return nil
            }
            return event
        }

        logger.warning("Hotkey registered: Option+Space")
    }

    @objc private func showPanel() {
        searchPanel.show()
    }
}
