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
