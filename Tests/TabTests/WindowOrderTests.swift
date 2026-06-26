import Testing
import CoreGraphics
@testable import Tab

/// Exercises `WindowEnumerator.orderByMRU` — the function that decides what order
/// windows appear in the switcher. Every case constructs a handful of windows and the
/// recency state behind them (which windows/apps were used most recently, and which app
/// is frontmost), runs the sort, and checks the window ids that come back. No AppKit and
/// no live windows are involved, so the behaviour is fully deterministic.
///
/// The cases below walk through: ordering by individual window recency, the rule that an
/// untouched window of the frontmost app must not jump forward with its focused sibling,
/// the app-recency fallback before any window has been focused, the original two-window
/// regression, and a few stability/edge checks.
///
/// Written with swift-testing (not XCTest) because the project builds under SwiftPM with
/// the Command Line Tools, where XCTest isn't available.
struct WindowOrderTests {

    // Apps under test, by pid.
    let appA: pid_t = 1
    let appB: pid_t = 2
    let appC: pid_t = 3
    let appD: pid_t = 4

    // Windows, by CGWindowID. A owns two (a1, a2); the rest own one each.
    let a1: CGWindowID = 11
    let a2: CGWindowID = 12
    let b1: CGWindowID = 21
    let c1: CGWindowID = 31
    let d1: CGWindowID = 41

    private func win(_ pid: pid_t, _ wid: CGWindowID?, app: String = "App", title: String = "Title") -> WindowInfo {
        WindowInfo(pid: pid, appName: app, icon: nil, title: title,
                   isMinimized: false, isHidden: false, cgWindowID: wid, axWindow: nil)
    }

    /// Runs the resolver and returns just the window ids, in display order.
    private func order(_ windows: [WindowInfo],
                       appOrder: [pid_t],
                       windowOrder: [CGWindowID],
                       frontmost: pid_t?) -> [CGWindowID?] {
        WindowEnumerator.orderByMRU(windows, appOrder: appOrder, windowOrder: windowOrder,
                                    frontmostPID: frontmost).map(\.cgWindowID)
    }

    // MARK: Ordering by window recency

    @Test func seenWindowsFollowWindowOrder() {
        let windows = [win(appB, b1), win(appD, d1), win(appC, c1)]
        let result = order(windows, appOrder: [appD, appC, appB],
                           windowOrder: [d1, c1, b1], frontmost: appD)
        #expect(result == [d1, c1, b1])
    }

    @Test func focusingOneWindowPromotesOnlyThatWindow() {
        // a1 was most recent, then b1; focusing a2 puts a2 first and leaves a1 put.
        let windows = [win(appA, a1), win(appA, a2), win(appB, b1)]
        let result = order(windows, appOrder: [appA, appB],
                           windowOrder: [a2, a1, b1], frontmost: appA)
        #expect(result == [a2, a1, b1])
    }

    // MARK: Untouched windows of the frontmost app

    @Test func untouchedWindowOfFrontmostAppSortsLast() {
        // a2 is focused (frontmost), a1 has never been focused. a1 must NOT ride a2's
        // coattails to the top just because their app is frontmost — it sorts last.
        let windows = [win(appA, a1), win(appA, a2), win(appB, b1), win(appC, c1)]
        let result = order(windows, appOrder: [appA, appB, appC],
                           windowOrder: [a2, b1, c1], frontmost: appA)
        #expect(result == [a2, b1, c1, a1])
    }

    @Test func untouchedWindowOfBackgroundAppKeepsAppRecency() {
        // b has two windows, neither seen; b is NOT frontmost, so they sort by app
        // recency among the unseen, ahead of an even-older app's window.
        let b2: CGWindowID = 22
        let windows = [win(appA, a1), win(appB, b1), win(appB, b2), win(appC, c1)]
        let result = order(windows, appOrder: [appA, appB, appC],
                           windowOrder: [a1], frontmost: appA)
        #expect(result == [a1, b1, b2, c1])
    }

    // MARK: Fallback to app recency before anything is focused

    @Test func emptyWindowOrderFallsBackToAppOrder() {
        // Cold start: nothing focused yet. Order follows app recency, frontmost first.
        let windows = [win(appC, c1), win(appA, a2), win(appB, b1), win(appD, d1)]
        let result = order(windows, appOrder: [appA, appB, appC, appD],
                           windowOrder: [], frontmost: nil)
        #expect(result == [a2, b1, c1, d1])
    }

    // MARK: The two-window regression

    /// The reported bug. Order was D, C, B, A1, A2; the user focuses A2. Expected
    /// A2, D, C, B, A1 — but the old per-app sort produced A2, A1, D, C, B because it
    /// dragged every window of the activated app to the front together.
    @Test func focusingSecondWindowDoesNotDragSiblingForward() {
        let windows = [win(appA, a1), win(appA, a2),
                       win(appB, b1), win(appC, c1), win(appD, d1)]
        let result = order(windows,
                           appOrder: [appA, appD, appC, appB],
                           windowOrder: [a2, d1, c1, b1],
                           frontmost: appA)
        #expect(result == [a2, d1, c1, b1, a1])
    }

    // MARK: Stability and edge cases

    @Test func stableWithinSameTier() {
        // Two unseen windows of the same (non-frontmost) app keep input order.
        let b2: CGWindowID = 22
        let windows = [win(appB, b1), win(appB, b2)]
        let result = order(windows, appOrder: [appB], windowOrder: [], frontmost: appA)
        #expect(result == [b1, b2])
    }

    @Test func windowWithoutIDTreatedAsUnseen() {
        // A window with no CGWindowID can't be in windowOrder; it falls to the unseen
        // tier rather than colliding with a real id.
        let windows = [win(appB, nil), win(appA, a1)]
        let result = order(windows, appOrder: [appA, appB], windowOrder: [a1], frontmost: appA)
        #expect(result == [a1, nil])
    }
}
