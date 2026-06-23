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

    /// Collapses native macOS tab groups and exact duplicates, independent of
    /// which Space you're viewing from. Native tabs are several windows of one app
    /// stacked at the *identical* frame; we keep one per (app, frame). Full-screen
    /// windows are exempt — each occupies its own Space and must all show — and are
    /// detected by their size matching a whole screen (a maximized window is shorter
    /// by the menu-bar height).
    private func deduplicate(_ candidates: [Candidate]) -> [WindowInfo] {
        let fullScreenSizes = NSScreen.screens.map { $0.frame.size }
        func isFullScreen(_ b: CGRect) -> Bool {
            b.width > 0 && fullScreenSizes.contains { abs($0.width - b.width) < 2 && abs($0.height - b.height) < 2 }
        }
        func frameKey(_ pid: pid_t, _ b: CGRect) -> String {
            "\(pid)\u{1}\(Int(b.minX)),\(Int(b.minY)),\(Int(b.width)),\(Int(b.height))"
        }

        // On-screen first, then AX-backed, so the active tab is the representative
        // we keep when we're on its Space.
        let sorted = candidates.enumerated().sorted { lhs, rhs in
            if lhs.element.onscreen != rhs.element.onscreen { return lhs.element.onscreen }
            let lax = lhs.element.info.axWindow != nil, rax = rhs.element.info.axWindow != nil
            if lax != rax { return lax }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var result: [WindowInfo] = []
        var seenTitle = Set<String>()
        var seenFrame = Set<String>()
        for candidate in sorted {
            let info = candidate.info
            let titleKey = "\(info.pid)\u{1}\(info.title)"
            if seenTitle.contains(titleKey) { continue }

            let hasFrame = candidate.bounds.width > 0 && candidate.bounds.height > 0
            if hasFrame, !isFullScreen(candidate.bounds) {
                let key = frameKey(info.pid, candidate.bounds)
                if seenFrame.contains(key) { continue }   // stacked tab at the same frame
                seenFrame.insert(key)
            }

            result.append(info)
            seenTitle.insert(titleKey)
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
