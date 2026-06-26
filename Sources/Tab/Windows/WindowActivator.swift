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
        let isHidden = info.isHidden

        let work = {
            // A hidden app (⌘H) must be unhidden before its window can be raised.
            if isHidden {
                NSRunningApplication(processIdentifier: pid)?.unhide()
            }
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

        // Raising one of our own windows (Tab shows in the switcher while Settings is
        // open) services kAXRaiseAction in-process and drives AppKit window ordering,
        // which must run on the main thread. Other apps go off-main so a slow target
        // can't stall the switcher — we never block on ourselves.
        if pid == getpid() {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        }
    }
}
