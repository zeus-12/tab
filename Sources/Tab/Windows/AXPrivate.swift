import Foundation
import ApplicationServices
import CoreGraphics

/// Private AppKit/HIServices function that returns the CoreGraphics window id for
/// an Accessibility element. There is no public API for this mapping, and the
/// alternatives (matching by title + bounds) break whenever an app has two
/// windows with the same title — so we link the private symbol directly, the
/// same way AltTab and similar tools do.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Returns the CGWindowID for an AX window element, or nil if it can't be mapped.
func cgWindowID(of element: AXUIElement) -> CGWindowID? {
    var id: CGWindowID = 0
    return _AXUIElementGetWindow(element, &id) == .success ? id : nil
}

/// Private: builds an AXUIElement from a "remote token". This is the only way to
/// get an AX handle for a window on *another* Space — `kAXWindowsAttribute` only
/// returns current-Space windows.
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

/// Finds the AX element for a specific window (by CGWindowID) of an app, even when
/// the window is on another Space. Brute-forces the app's AX element ids (the
/// remote-token layout AltTab reverse-engineered: pid, 0, "coco", elementId),
/// matching on subrole == window and the window id. Time-bounded so a busy app
/// can't stall us.
func axWindowElement(pid: pid_t, windowID: CGWindowID, deadline: Date) -> AXUIElement? {
    var token = Data(count: 20)
    token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
    token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })

    var elementID: UInt64 = 0
    while elementID < 2000 {
        token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
        if let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() {
            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = subroleValue as? String
            if (subrole == (kAXStandardWindowSubrole as String) || subrole == "AXDialog"),
               cgWindowID(of: element) == windowID {
                return element
            }
        }
        if Date() > deadline { break }
        elementID += 1
    }
    return nil
}
