import Carbon
import AppKit
import os

private let logger = Logger(subsystem: "BetterSearch.BS", category: "hotkey")

/// Reliable global hotkey using Carbon's RegisterEventHotKey API
/// This is the same approach used by Alfred, Raycast, and other macOS utilities
class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void

    /// Register a global hotkey
    /// - Parameters:
    ///   - keyCode: Carbon virtual key code (e.g., 49 for Space)
    ///   - modifiers: Carbon modifier flags
    ///   - callback: Called when hotkey is pressed
    init(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback
        register(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        unregister()
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        // Store self in a global so the C callback can reach it
        GlobalHotkeyStorage.shared = self

        // Install Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let hotkey = GlobalHotkeyStorage.shared else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async {
                    hotkey.callback()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            logger.error("Failed to install event handler: \(status)")
            return
        }

        // Register the hotkey
        let hotkeyID = EventHotKeyID(signature: OSType(0x42530000), id: 1) // "BS\0\0"
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus == noErr {
            logger.warning("Global hotkey registered successfully (keyCode=\(keyCode), mods=\(modifiers))")
        } else {
            logger.error("Failed to register hotkey: \(regStatus)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        GlobalHotkeyStorage.shared = nil
    }
}

/// Storage to bridge between C callback and Swift
private class GlobalHotkeyStorage {
    static var shared: GlobalHotkey?
}

// MARK: - Carbon modifier constants

extension GlobalHotkey {
    /// Cmd + Shift + Space
    static func cmdShiftSpace(callback: @escaping () -> Void) -> GlobalHotkey {
        // Carbon key codes: Space = 49
        // Carbon modifiers: cmdKey = 256 (0x100), shiftKey = 512 (0x200)
        return GlobalHotkey(
            keyCode: 49,
            modifiers: UInt32(cmdKey | shiftKey),
            callback: callback
        )
    }

    /// Option + Space
    static func optionSpace(callback: @escaping () -> Void) -> GlobalHotkey {
        return GlobalHotkey(
            keyCode: 49,
            modifiers: UInt32(optionKey),
            callback: callback
        )
    }
}
