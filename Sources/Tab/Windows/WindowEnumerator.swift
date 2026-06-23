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

/// Enumerates windows by merging two sources:
///   1. Accessibility (authoritative): current-Space + minimized windows, with
///      accurate titles, minimized state, and a handle to raise.
///   2. The window-server list (`CGWindowListCopyWindowInfo`): adds windows on
///      *other* Spaces that AX can't see (filtered to real windows by requiring a
///      non-empty title).
/// then de-duplicates — collapsing native macOS tab groups (background tabs are
/// separate windows stacked at the same frame as the on-screen active tab).
final class WindowEnumerator {
    /// Caps how long a slow/hung app can block an AX query, keeping the switcher
    /// (and the event tap driving it) responsive.
    private let axTimeout: Float = 0.25

    private struct CGInfo {
        let pid: pid_t
        let layer: Int
        let bounds: CGRect
        let onscreen: Bool
        let name: String
    }

    private struct Candidate {
        let info: WindowInfo
        let bounds: CGRect
        let onscreen: Bool
    }

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
        let appsByPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

        // Window-server list once, indexed by window id.
        var cgByWid: [CGWindowID: CGInfo] = [:]
        var cgOrder: [CGWindowID] = []
        if let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for entry in list {
                guard let layer = entry[kCGWindowLayer as String] as? Int,
                      let widInt = entry[kCGWindowNumber as String] as? Int,
                      let pidInt = entry[kCGWindowOwnerPID as String] as? Int else { continue }
                var bounds = CGRect.zero
                if let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                   let rect = CGRect(dictionaryRepresentation: dict) { bounds = rect }
                let wid = CGWindowID(widInt)
                cgByWid[wid] = CGInfo(
                    pid: pid_t(pidInt),
                    layer: layer,
                    bounds: bounds,
                    onscreen: (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false,
                    name: (entry[kCGWindowName as String] as? String) ?? ""
                )
                cgOrder.append(wid)
            }
        }

        var candidates: [Candidate] = []
        var seenWids = Set<CGWindowID>()
        // Titles of inactive tabs (per app), discovered via AXTabGroup. Their windows
        // appear in the window-server list but aren't real separate windows, so we
        // suppress them by (pid, title).
        var inactiveTabKeys = Set<String>()

        // Pass 1 — Accessibility. Only the active tab of a tab group is a real AX
        // window, so this naturally yields one entry per tabbed window.
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

                // If this window is the active tab of a tab group, record its
                // inactive siblings' titles so the window-server pass skips them.
                if let tabs = tabTitles(ofWindow: axWindow) {
                    Log.info("tabgroup [\(app.localizedName ?? "")]: \(tabs)")
                    for tab in tabs where tab != rawTitle {
                        inactiveTabKeys.insert("\(app.processIdentifier)\u{1}\(tab)")
                    }
                }

                let wid = cgWindowID(of: axWindow)
                if let wid { seenWids.insert(wid) }
                let cg = wid.flatMap { cgByWid[$0] }

                candidates.append(Candidate(
                    info: WindowInfo(
                        pid: app.processIdentifier,
                        appName: app.localizedName ?? "",
                        icon: app.icon,
                        title: rawTitle.isEmpty ? (app.localizedName ?? "") : rawTitle,
                        isMinimized: isMinimized,
                        cgWindowID: wid,
                        axWindow: axWindow
                    ),
                    bounds: cg?.bounds ?? .zero,
                    onscreen: cg?.onscreen ?? false
                ))
            }
        }

        // Pass 2 — window-server list, for windows on other Spaces (no AX handle).
        for wid in cgOrder where !seenWids.contains(wid) {
            guard let cg = cgByWid[wid], cg.layer == 0, let app = appsByPID[cg.pid] else { continue }
            guard cg.bounds.width >= 40, cg.bounds.height >= 40 else { continue }
            guard !cg.name.isEmpty else { continue }   // helper/service windows have no title
            if inactiveTabKeys.contains("\(cg.pid)\u{1}\(cg.name)") { continue }   // inactive tab, not a window
            seenWids.insert(wid)
            candidates.append(Candidate(
                info: WindowInfo(
                    pid: cg.pid,
                    appName: app.localizedName ?? "",
                    icon: app.icon,
                    title: cg.name,
                    isMinimized: false,
                    cgWindowID: wid,
                    axWindow: nil
                ),
                bounds: cg.bounds,
                onscreen: cg.onscreen
            ))
        }

        let result = deduplicate(candidates)
            .filter { includeMinimized || !$0.isMinimized }

        var windows = result
        if currentSpaceOnly {
            let onScreen = Self.onScreenWindowIDs()
            windows = windows.filter { info in info.cgWindowID.map { onScreen.contains($0) } ?? false }
        }

        let ordered = orderByMRU(windows, mruOrder: mruOrder)
        Log.info("enum: \(ordered.count) windows (minimized=\(includeMinimized), currentSpace=\(currentSpaceOnly))")
        for window in ordered {
            Log.info("  win: \(window.appName) | \(window.title) | ax=\(window.axWindow != nil)")
        }
        return ordered
    }

    /// Drops exact duplicates by (app, title) — e.g. an AX window whose CGWindowID
    /// lookup failed and reappears from the window-server pass. Tab groups are
    /// already handled in `enumerateWindows` via AXTabGroup, and genuinely separate
    /// windows keep their distinct titles, so no frame guessing is needed.
    private func deduplicate(_ candidates: [Candidate]) -> [WindowInfo] {
        // AX-backed first, so the real window wins over a window-server duplicate.
        let sorted = candidates.enumerated().sorted { lhs, rhs in
            let lax = lhs.element.info.axWindow != nil, rax = rhs.element.info.axWindow != nil
            if lax != rax { return lax }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var result: [WindowInfo] = []
        var seenTitle = Set<String>()
        for candidate in sorted {
            let key = "\(candidate.info.pid)\u{1}\(candidate.info.title)"
            guard seenTitle.insert(key).inserted else { continue }
            result.append(candidate.info)
        }
        return result
    }

    private func orderByMRU(_ windows: [WindowInfo], mruOrder: [pid_t]) -> [WindowInfo] {
        var rankByPID: [pid_t: Int] = [:]
        for (index, pid) in mruOrder.enumerated() { rankByPID[pid] = index }
        let rank: (pid_t) -> Int = { rankByPID[$0] ?? Int.max }
        return windows.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element.pid), r = rank(rhs.element.pid)
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
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
