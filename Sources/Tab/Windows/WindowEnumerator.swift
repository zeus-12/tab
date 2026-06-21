import AppKit
import ApplicationServices

/// A single switchable window, backed by its live Accessibility element so we can
/// raise/unminimize it later.
struct WindowInfo {
    let pid: pid_t
    let appName: String
    let icon: NSImage?
    let title: String
    let isMinimized: Bool
    let axWindow: AXUIElement
}

/// Enumerates standard windows of every regular (Dock-visible) application using
/// the Accessibility API. This works across all Spaces and is entirely public —
/// no private SkyLight calls. Requires Accessibility permission; without it the
/// per-app window queries simply fail and we return an empty list.
final class WindowEnumerator {
    func enumerateWindows(excludedBundleIDs: Set<String>, includeMinimized: Bool) -> [WindowInfo] {
        var ordered = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

        // Put the currently-active app first so the classic "switch to previous
        // window" lands on the second entry.
        if let front = NSWorkspace.shared.frontmostApplication,
           let idx = ordered.firstIndex(of: front) {
            ordered.remove(at: idx)
            ordered.insert(front, at: 0)
        }

        var result: [WindowInfo] = []
        for app in ordered {
            guard let bundleID = app.bundleIdentifier, !excludedBundleIDs.contains(bundleID) else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }

            for window in windows {
                guard let info = windowInfo(for: window, app: app) else { continue }
                if !includeMinimized && info.isMinimized { continue }
                result.append(info)
            }
        }
        return result
    }

    private func windowInfo(for window: AXUIElement, app: NSRunningApplication) -> WindowInfo? {
        // Only standard windows — excludes sheets, popovers, tool palettes, etc.
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
        guard (subroleValue as? String) == (kAXStandardWindowSubrole as String) else { return nil }

        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        let rawTitle = (titleValue as? String) ?? ""
        let appName = app.localizedName ?? ""
        let title = rawTitle.isEmpty ? appName : rawTitle

        var minimizedValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
        let isMinimized = (minimizedValue as? Bool) ?? false

        return WindowInfo(
            pid: app.processIdentifier,
            appName: appName,
            icon: app.icon,
            title: title,
            isMinimized: isMinimized,
            axWindow: window
        )
    }
}
