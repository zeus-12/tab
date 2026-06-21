import Foundation
import CoreGraphics

/// A session-level event tap that sees keyboard events before the rest of the
/// system. This is the only reliable way to override **Command+Tab**: we consume
/// the event so the built-in macOS app switcher never receives it.
///
/// Creating a keyboard event tap requires Accessibility permission — `tapCreate`
/// returns nil without it. We use that as the definitive, no-relaunch-needed
/// signal for whether permission is live.
@MainActor
final class KeyInterceptor {
    /// Return `true` to consume the key (stop it propagating to other apps).
    var onKeyDown: ((_ keyCode: Int64, _ flags: CGEventFlags) -> Bool)?
    var onFlagsChanged: ((_ flags: CGEventFlags) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// Attempts to create the tap. Returns true on success (Accessibility granted).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
                 | CGEventMask(1) << CGEventType.flagsChanged.rawValue
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return MainActor.assumeIsolated { interceptor.process(type: type, event: event) }
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The OS disables a tap whose callback is too slow; just re-enable it.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let consumed = onKeyDown?(keyCode, event.flags) ?? false
            return consumed ? nil : Unmanaged.passUnretained(event)

        case .flagsChanged:
            onFlagsChanged?(event.flags)
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
