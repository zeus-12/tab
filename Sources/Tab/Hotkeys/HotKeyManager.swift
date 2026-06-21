import AppKit
import Carbon.HIToolbox

/// Registers true system-wide hotkeys via the Carbon API — the only mechanism on
/// macOS that fires even when another app is frontmost. Each registered combo
/// re-fires its callback on every physical press, which is what lets the user
/// hold ⌥ and tap Tab repeatedly to cycle.
@MainActor
final class HotKeyManager {
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private let signature: OSType = 0x54414231 // 'TAB1'

    init() {
        installHandler()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers hotkey events on the main run loop.
            MainActor.assumeIsolated { manager.actions[hkID.id]?() }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Tab: failed to register hotkey (status \(status))")
            return 0
        }
        hotKeyRefs[id] = ref
        actions[id] = action
        return id
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }
}
