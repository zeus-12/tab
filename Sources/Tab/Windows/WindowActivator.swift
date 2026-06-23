import AppKit
import ApplicationServices

/// Brings a selected window to the front. When we have an Accessibility handle,
/// raising via AX follows the window to whichever Space it lives on (the OS
/// animates the Space switch). For windows on other Spaces that AX hasn't
/// realized, we fall back to activating the app, which still switches to it.
enum WindowActivator {
    static func activate(_ info: WindowInfo) {
        if let axWindow = info.axWindow {
            if info.isMinimized {
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            // Make this the app's focused window so keyboard focus lands correctly.
            AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(info.pid),
                kAXFocusedWindowAttribute as CFString,
                axWindow
            )
        }
        NSRunningApplication(processIdentifier: info.pid)?.activate()
    }
}
