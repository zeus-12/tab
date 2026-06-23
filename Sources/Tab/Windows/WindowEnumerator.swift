import AppKit
import ApplicationServices
import CoreGraphics

/// A single switchable window. `axWindow` is the Accessibility handle used to
/// raise/unminimize it; it's nil for windows on other Spaces that AX hasn't
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

/// Enumerates windows from two sources and merges them:
///   1. Accessibility (authoritative): current-Space + minimized windows, with
///      accurate titles and a handle to raise. This is where minimized state and
///      the standard-window filter come from.
///   2. The window-server list (`CGWindowListCopyWindowInfo`): adds windows on
///      *other* Spaces that AX can't see. These are filtered to real windows by
///      requiring a non-empty title (helper/service windows have none).
final class WindowEnumerator {
    /// Caps how long a slow/hung app can block an AX query, so the switcher (and
    /// the event tap driving it) stays responsive.
    private let axTimeout: Float = 0.25

    func enumerateWindows(
        excludedBundleIDs: Set<String>,
        includeMinimized: Bool,
        currentSpaceOnly: Bool,
        mruOrder: [pid_t]
    ) -> [WindowInfo] {
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && (app.bundleIdentifier.map { !excludedBundleIDs.contains($0) } ?? false)
        }

        var result: [WindowInfo] = []
        var seen = Set<CGWindowID>()

        // Pass 1 — Accessibility.
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, axTimeout)

            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }

            for axWindow in windows {
                var subrole: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subrole)
                guard (subrole as? String) == (kAXStandardWindowSubrole as String) else { continue }

                var minimizedValue: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedValue)
                let isMinimized = (minimizedValue as? Bool) ?? false

                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
                let rawTitle = (titleValue as? String) ?? ""

                let wid = cgWindowID(of: axWindow)
                if let wid { seen.insert(wid) }

                result.append(WindowInfo(
                    pid: app.processIdentifier,
                    appName: app.localizedName ?? "",
                    icon: app.icon,
                    title: rawTitle.isEmpty ? (app.localizedName ?? "") : rawTitle,
                    isMinimized: isMinimized,
                    cgWindowID: wid,
                    axWindow: axWindow
                ))
            }
        }

        // Pass 2 — window-server list, for windows on other Spaces (no AX handle).
        let appsByPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        if let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for entry in list {
                guard (entry[kCGWindowLayer as String] as? Int) == 0,
                      let widInt = entry[kCGWindowNumber as String] as? Int,
                      let pidInt = entry[kCGWindowOwnerPID as String] as? Int else { continue }
                let wid = CGWindowID(widInt)
                if seen.contains(wid) { continue }

                guard let app = appsByPID[pid_t(pidInt)] else { continue }
                if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
                if let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                   let rect = CGRect(dictionaryRepresentation: bounds),
                   rect.width < 40 || rect.height < 40 { continue }

                // Real top-level windows carry a title; helper/service/preview
                // windows don't — that's how we drop the junk.
                let cgName = (entry[kCGWindowName as String] as? String) ?? ""
                guard !cgName.isEmpty else { continue }

                seen.insert(wid)
                result.append(WindowInfo(
                    pid: pid_t(pidInt),
                    appName: app.localizedName ?? "",
                    icon: app.icon,
                    title: cgName,
                    isMinimized: false,
                    cgWindowID: wid,
                    axWindow: nil
                ))
            }
        }

        // De-duplicate by app + title. Pass 1 (AX) runs first, so when a window
        // reappears from the window-server list — e.g. its CGWindowID lookup failed
        // in AX so it wasn't marked seen — the AX copy is the one kept.
        var seenKeys = Set<String>()
        result = result.filter { seenKeys.insert("\($0.pid)\u{1}\($0.title)").inserted }

        // Filters.
        if !includeMinimized {
            result.removeAll { $0.isMinimized }
        }
        if currentSpaceOnly {
            let onScreen = Self.onScreenWindowIDs()
            result = result.filter { info in info.cgWindowID.map { onScreen.contains($0) } ?? false }
        }

        // Order by most-recently-used app, stable within each app.
        var rankByPID: [pid_t: Int] = [:]
        for (index, pid) in mruOrder.enumerated() { rankByPID[pid] = index }
        let rank: (pid_t) -> Int = { rankByPID[$0] ?? Int.max }
        let ordered = result.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element.pid), r = rank(rhs.element.pid)
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)

        Log.info("enum: \(ordered.count) windows (minimized=\(includeMinimized), currentSpace=\(currentSpaceOnly))")
        for window in ordered {
            Log.info("  win: \(window.appName) | \(window.title) | ax=\(window.axWindow != nil)")
        }
        return ordered
    }

    /// CGWindowIDs of windows currently on screen — i.e. on the active Space.
    private static func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids = Set<CGWindowID>()
        for entry in list {
            if let number = entry[kCGWindowNumber as String] as? Int { ids.insert(CGWindowID(number)) }
        }
        return ids
    }
}
