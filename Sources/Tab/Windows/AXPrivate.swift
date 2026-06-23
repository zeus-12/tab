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

/// If a window has OS-level tabs, returns the titles of all its tabs (the active
/// one plus the inactive siblings). Returns nil for a non-tabbed window.
///
/// Only the active tab is a real window; inactive tabs are `AXTabButton`s inside
/// the active window's `AXTabGroup`. This is the one reliable way to identify
/// tabs — see AltTab's TabbedWindowDetection notes; no window property exposes it.
func tabTitles(ofWindow window: AXUIElement) -> [String]? {
    var childrenValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenValue) == .success,
          let children = childrenValue as? [AXUIElement] else { return nil }

    for child in children {
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
        guard (roleValue as? String) == "AXTabGroup" else { continue }

        var tabsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &tabsValue) == .success,
              let tabs = tabsValue as? [AXUIElement] else { return nil }

        var titles: [String] = []
        for tab in tabs {
            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(tab, kAXSubroleAttribute as CFString, &subroleValue)
            guard (subroleValue as? String) == "AXTabButton" else { continue }   // skips the "+" button
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(tab, kAXTitleAttribute as CFString, &titleValue)
            if let title = titleValue as? String { titles.append(title) }
        }
        return titles.count >= 2 ? titles : nil
    }
    return nil
}
