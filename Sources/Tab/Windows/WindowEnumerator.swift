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

/// Enumerates windows by merging two sources, then filtering to real windows:
///   1. Accessibility (authoritative): current-Space + minimized windows, with
///      accurate titles, minimized state, and a handle to raise.
///   2. The window-server list (`CGWindowListCopyWindowInfo`): adds windows on
///      *other* Spaces that AX can't see.
/// Both are filtered against the CGS "visible" window set, which drops phantoms
/// (closed/hidden windows lingering in the list) and inactive tabs — keeping
/// only genuine windows on any Space. Minimized windows are exempt.
final class WindowEnumerator {
    /// Caps how long a slow/hung app can block an AX query, keeping the switcher
    /// (and the event tap driving it) responsive.
    private let axTimeout: Float = 0.25

    private struct CGInfo {
        let pid: pid_t
        let layer: Int
        let bounds: CGRect
        let name: String
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

        // Real windows across every Space (drops phantoms / inactive tabs / hidden).
        let visibleWids = CGS.visibleWindowIDsAcrossAllSpaces()

        // Window-server list once, indexed by window id (for metadata of other-Space windows).
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
                    name: (entry[kCGWindowName as String] as? String) ?? ""
                )
                cgOrder.append(wid)
            }
        }

        var result: [WindowInfo] = []
        var seenWids = Set<CGWindowID>()

        // A window is real if it's currently visible somewhere, or minimized (AX
        // confirms those — they're legitimately not rendered), or we couldn't get a
        // window id to check. If the CGS query failed, don't filter at all.
        func isReal(wid: CGWindowID?, isMinimized: Bool) -> Bool {
            if visibleWids.isEmpty || isMinimized { return true }
            guard let wid else { return true }
            return visibleWids.contains(wid)
        }

        // Pass 1 — Accessibility (only the active tab of a tab group is an AX window).
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, axTimeout)

            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }

            for axWindow in windows {
                var subroleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleValue)
                let subrole = subroleValue as? String

                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
                let rawTitle = (titleValue as? String) ?? ""

                // Accept standard windows, plus titled dialogs: a minimized window
                // (or a hidden app's window) reports subrole AXDialog, so requiring
                // AXStandardWindow alone drops every minimized window. Titleless
                // dialogs are side panels / popovers we still skip.
                let isStandard = subrole == (kAXStandardWindowSubrole as String)
                let isTitledDialog = subrole == "AXDialog" && !rawTitle.isEmpty
                guard isStandard || isTitledDialog else { continue }

                var minimizedValue: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedValue)
                let isMinimized = (minimizedValue as? Bool) ?? false

                let wid = cgWindowID(of: axWindow)
                guard isReal(wid: wid, isMinimized: isMinimized) else { continue }   // drop phantoms
                if let wid { seenWids.insert(wid) }

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

        // Pass 2 — window-server list, for real windows on other Spaces (no AX handle).
        for wid in cgOrder where !seenWids.contains(wid) {
            guard visibleWids.isEmpty || visibleWids.contains(wid) else { continue }   // drop phantoms
            guard let cg = cgByWid[wid], cg.layer == 0, let app = appsByPID[cg.pid] else { continue }
            guard cg.bounds.width >= 40, cg.bounds.height >= 40 else { continue }
            guard !cg.name.isEmpty else { continue }
            seenWids.insert(wid)
            result.append(WindowInfo(
                pid: cg.pid,
                appName: app.localizedName ?? "",
                icon: app.icon,
                title: cg.name,
                isMinimized: false,
                cgWindowID: wid,
                axWindow: nil
            ))
        }

        // Drop exact (app, title) duplicates (e.g. an AX window whose id lookup failed
        // reappearing from the window-server pass).
        var seenTitle = Set<String>()
        result = result.filter { seenTitle.insert("\($0.pid)\u{1}\($0.title)").inserted }

        if !includeMinimized {
            result.removeAll { $0.isMinimized }
        }
        if currentSpaceOnly {
            let onScreen = Self.onScreenWindowIDs()
            // Minimized windows aren't on screen but belong to the current Space.
            result = result.filter { info in
                info.isMinimized || (info.cgWindowID.map { onScreen.contains($0) } ?? false)
            }
        }

        let ordered = orderByMRU(result, mruOrder: mruOrder)
        Log.info("enum: \(ordered.count) windows (minimized=\(includeMinimized), currentSpace=\(currentSpaceOnly))")
        return ordered
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
