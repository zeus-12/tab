import AppKit
import ApplicationServices
import CoreGraphics

// Private APIs for reliably focusing a window — including one on another Space.
// macOS 14 downgraded NSRunningApplication.activate() to an advisory request, so
// it no longer moves key focus across apps/Spaces on its own (the app's name
// lights up in the menu bar but no window appears). The SkyLight sequence below —
// used by AltTab and yabai — fronts the specific window by id and switches to its
// Space. Linked directly since there's no public equivalent.

@_silgen_name("GetProcessForPID") @discardableResult
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo") @discardableResult
func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

enum WindowFocus {
    private static let userGenerated: UInt32 = 0x200

    /// Brings the window to the front, switching Space if it lives on another one.
    static func raise(pid: pid_t, cgWindowID: CGWindowID, axWindow: AXUIElement?) {
        // For a window on another Space, AX never handed us a handle; build one from
        // its id. The kAXRaiseAction on it is what reliably makes macOS switch Space.
        let element = axWindow ?? axWindowElement(
            pid: pid, windowID: cgWindowID, deadline: Date().addingTimeInterval(0.2)
        )

        var psn = ProcessSerialNumber()
        guard GetProcessForPID(pid, &psn) == noErr else {
            DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid)?.activate() }
            return
        }
        // Front the process + this specific window (raises only it; switches Space).
        _SLPSSetFrontProcessWithOptions(&psn, cgWindowID, userGenerated)
        // Make it key via a synthetic click aimed just outside the window.
        makeKeyWindow(&psn, cgWindowID)
        // Raise within the app's own window stack — this drives the Space switch.
        if let element {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    /// Posts a synthetic left mouse down+up to the WindowServer to make `wid` key
    /// (no public API moves key focus across apps). Byte offsets are the
    /// reverse-engineered CGSEventRecord layout used by yabai/Hammerspoon; the
    /// click point is just outside the frame so it keys the window without hitting
    /// any of its content.
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
        var wid = wid
        var point = CGPoint(x: -1, y: -1)
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xf8                                       // record length
        bytes[0x3a] = 0x10                                       // undocumented flag
        memcpy(&bytes[0x3c], &wid, MemoryLayout<CGWindowID>.size)   // target window id
        memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)   // window-relative point
        bytes[0x08] = 0x01                                       // kCGEventLeftMouseDown
        SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02                                       // kCGEventLeftMouseUp
        SLPSPostEventRecordTo(&psn, &bytes)
    }
}
