import AppKit
import ApplicationServices

/// Brings a selected window to the front. Raising via Accessibility will follow
/// the window to whichever Space it lives on (the OS animates the Space switch),
/// which is exactly the behavior we want.
enum WindowActivator {
    static func activate(_ info: WindowInfo) {
        if info.isMinimized {
            AXUIElementSetAttributeValue(info.axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(info.axWindow, kAXRaiseAction as CFString)

        // Make this the app's focused window, then activate the app so keyboard
        // focus lands on the right window rather than just the app's last one.
        let appElement = AXUIElementCreateApplication(info.pid)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, info.axWindow)

        NSRunningApplication(processIdentifier: info.pid)?.activate()
    }
}
