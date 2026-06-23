import AppKit
import ApplicationServices
import CoreGraphics

/// A single switchable window. `axWindow` is the Accessibility handle used to
/// raise/unminimize it; it can be nil for windows on other Spaces that AX hasn't
/// realized — those are raised by activating their app instead.
struct WindowInfo {
    let pid: pid_t
    let appName: String
    let icon: NSImage?
    let title: String
    let isMinimized: Bool
    let cgWindowID: CGWindowID?
    let axWindow: AXUIElement?
}

/// Enumerates windows from the window server's full list (`CGWindowListCopyWindowInfo`
/// without the on-screen flag), which spans **all Spaces** — unlike the Accessibility
/// API, which only reliably reports the current Space. Each window is then enriched
/// from AX (title, minimized state, and a handle to raise) when AX has realized it.
final class WindowEnumerator {
    func enumerateWindows(
        excludedBundleIDs: Set<String>,
        includeMinimized: Bool,
        currentSpaceOnly: Bool,
        mruOrder: [pid_t]
    ) -> [WindowInfo] {
        // No on-screen flag → windows across every Space (and full-screen ones).
        // Current-Space scope just adds the on-screen flag back.
        var options: CGWindowListOption = [.excludeDesktopElements]
        if currentSpaceOnly { options.insert(.optionOnScreenOnly) }

        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let appsByPID = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var axWindowsByPID: [pid_t: [CGWindowID: AXUIElement]] = [:]
        func axWindows(for pid: pid_t) -> [CGWindowID: AXUIElement] {
            if let cached = axWindowsByPID[pid] { return cached }
            var map: [CGWindowID: AXUIElement] = [:]
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
               let windows = value as? [AXUIElement] {
                for window in windows {
                    if let id = cgWindowID(of: window) { map[id] = window }
                }
            }
            axWindowsByPID[pid] = map
            return map
        }

        var result: [WindowInfo] = []
        var axMatched = 0
        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,                  // normal window layer
                  let widInt = entry[kCGWindowNumber as String] as? Int,
                  let pidInt = entry[kCGWindowOwnerPID as String] as? Int else { continue }
            let pid = pid_t(pidInt)
            let wid = CGWindowID(widInt)

            guard let app = appsByPID[pid], app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier, !excludedBundleIDs.contains(bundleID) else { continue }

            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            if let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: boundsDict),
               rect.width < 40 || rect.height < 40 { continue }   // skip tiny helper windows

            let cgName = (entry[kCGWindowName as String] as? String) ?? ""
            let axWindow = axWindows(for: pid)[wid]

            var isMinimized = false
            var title = ""
            if let ax = axWindow {
                // AX has realized this window (current Space): it's authoritative.
                // Filter to standard windows and read the real title + minimized state.
                axMatched += 1
                var subrole: CFTypeRef?
                AXUIElementCopyAttributeValue(ax, kAXSubroleAttribute as CFString, &subrole)
                if (subrole as? String) != (kAXStandardWindowSubrole as String) { continue }

                var minimized: CFTypeRef?
                AXUIElementCopyAttributeValue(ax, kAXMinimizedAttribute as CFString, &minimized)
                isMinimized = (minimized as? Bool) ?? false

                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(ax, kAXTitleAttribute as CFString, &titleValue)
                title = (titleValue as? String) ?? ""
            } else {
                // No AX handle (window on another Space). The window-server list is
                // full of helper/service/preview windows (empty title); real
                // top-level windows have a title. Require one to filter out the junk.
                if cgName.isEmpty { continue }
                title = cgName
            }

            if !includeMinimized && isMinimized { continue }

            let appName = app.localizedName ?? ""
            if title.isEmpty { title = cgName.isEmpty ? appName : cgName }

            result.append(WindowInfo(
                pid: pid,
                appName: appName,
                icon: app.icon,
                title: title,
                isMinimized: isMinimized,
                cgWindowID: wid,
                axWindow: axWindow
            ))
        }

        // Order by most-recently-used app, preserving the window server's z-order
        // within each app (stable sort).
        let rank: (pid_t) -> Int = { pid in mruOrder.firstIndex(of: pid) ?? Int.max }
        let ordered = result.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element.pid), r = rank(rhs.element.pid)
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)

        Log.info("enum: \(list.count) cg windows → \(ordered.count) shown (\(axMatched) AX-matched)")
        return ordered
    }
}
