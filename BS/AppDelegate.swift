import AppKit
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "app")

class AppDelegate: NSObject, NSApplicationDelegate {
    private var searchPanel: SearchPanel!
    private var statusItem: NSStatusItem!
    private var hotkey: GlobalHotkey?
    private var onboardingWindow: OnboardingWindow?

    private var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "onboardingCompleted") }
        set { UserDefaults.standard.set(newValue, forKey: "onboardingCompleted") }
    }

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

        if hasCompletedOnboarding {
            // Already set up — hide dock icon and go straight to menu bar mode
            hideDockIcon()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                for window in NSApp.windows where window !== self.searchPanel {
                    window.orderOut(nil)
                }
            }
        } else {
            // First launch — show onboarding with dock icon visible
            showOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if hasCompletedOnboarding {
            searchPanel.show()
        } else {
            showOnboarding()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey?.unregister()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        // Hide any SwiftUI windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows where window !== self.searchPanel && !(window is OnboardingWindow) {
                window.orderOut(nil)
            }
        }

        onboardingWindow = OnboardingWindow { [weak self] in
            guard let self else { return }
            self.hasCompletedOnboarding = true
            self.onboardingWindow = nil

            // Re-register hotkey now that we (hopefully) have permission
            self.setupHotkey()

            // Hide dock icon and switch to menu bar mode
            self.hideDockIcon()

            // Show the search panel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.searchPanel.show()
            }

            logger.warning("Onboarding completed")
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Dock Icon

    private func hideDockIcon() {
        NSApp.setActivationPolicy(.accessory)
        logger.warning("Dock icon hidden — menu bar mode")
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "BS Search")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Search (⌘⇧Space)", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Welcome", action: #selector(resetOnboarding), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit BS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Global Hotkey (Carbon API — same as Alfred/Raycast)

    private func setupHotkey() {
        hotkey?.unregister()
        hotkey = GlobalHotkey.cmdShiftSpace { [weak self] in
            logger.warning("Global hotkey Cmd+Shift+Space triggered")
            self?.searchPanel.toggle()
        }
    }

    @objc private func showPanel() {
        searchPanel.show()
    }

    @objc private func resetOnboarding() {
        hasCompletedOnboarding = false
        // Show dock icon temporarily for onboarding
        NSApp.setActivationPolicy(.regular)
        showOnboarding()
    }
}
