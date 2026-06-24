import AppKit
import ApplicationServices

/// Brings a selected window to the front. Runs off the main thread because AX/CGS
/// calls can block on a slow app, and we don't want to stall the switcher.
enum WindowActivator {
    static func activate(_ info: WindowInfo) {
        let pid = info.pid
        let cgWindowID = info.cgWindowID
        let axWindow = info.axWindow
        let isMinimized = info.isMinimized

        DispatchQueue.global(qos: .userInitiated).async {
            if isMinimized, let axWindow {
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }

            if let cgWindowID {
                WindowFocus.raise(pid: pid, cgWindowID: cgWindowID, axWindow: axWindow)
            } else {
                // No window id (rare): best effort via AX + app activation.
                if let axWindow {
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                }
                DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid)?.activate() }
            }
        }
    }
}
