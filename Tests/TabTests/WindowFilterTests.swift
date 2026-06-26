import Testing
import CoreGraphics
@testable import Tab

/// Covers `WindowEnumerator.keepAfterFilters` — the post-enumeration include/exclude
/// check that the "show minimized" / "show hidden apps" toggles and the current-Space
/// scope feed into. The hidden-apps feature lives here. Pure data in, Bool out.
struct WindowFilterTests {

    // MARK: Show / hide hidden apps

    @Test func hiddenWindowKeptWhenToggleOn() {
        #expect(WindowEnumerator.keepAfterFilters(
            isMinimized: false, isHidden: true, isOnScreen: false,
            includeMinimized: true, includeHidden: true, currentSpaceOnly: false))
    }

    @Test func hiddenWindowDroppedWhenToggleOff() {
        #expect(!WindowEnumerator.keepAfterFilters(
            isMinimized: false, isHidden: true, isOnScreen: false,
            includeMinimized: true, includeHidden: false, currentSpaceOnly: false))
    }

    @Test func visibleWindowUnaffectedByHiddenToggle() {
        #expect(WindowEnumerator.keepAfterFilters(
            isMinimized: false, isHidden: false, isOnScreen: true,
            includeMinimized: true, includeHidden: false, currentSpaceOnly: false))
    }

    // MARK: Show / hide minimized windows

    @Test func minimizedWindowDroppedWhenToggleOff() {
        #expect(!WindowEnumerator.keepAfterFilters(
            isMinimized: true, isHidden: false, isOnScreen: false,
            includeMinimized: false, includeHidden: true, currentSpaceOnly: false))
    }

    @Test func minimizedHiddenWindowNeedsBothToggles() {
        // A window that is both minimized and hidden is excluded if either toggle is off.
        #expect(!WindowEnumerator.keepAfterFilters(
            isMinimized: true, isHidden: true, isOnScreen: false,
            includeMinimized: false, includeHidden: true, currentSpaceOnly: false))
        #expect(WindowEnumerator.keepAfterFilters(
            isMinimized: true, isHidden: true, isOnScreen: false,
            includeMinimized: true, includeHidden: true, currentSpaceOnly: false))
    }

    // MARK: Current-Space scope

    @Test func currentSpaceDropsOffScreenWindow() {
        #expect(!WindowEnumerator.keepAfterFilters(
            isMinimized: false, isHidden: false, isOnScreen: false,
            includeMinimized: true, includeHidden: true, currentSpaceOnly: true))
    }

    @Test func currentSpaceKeepsOnScreenWindow() {
        #expect(WindowEnumerator.keepAfterFilters(
            isMinimized: false, isHidden: false, isOnScreen: true,
            includeMinimized: true, includeHidden: true, currentSpaceOnly: true))
    }

    @Test func currentSpaceKeepsMinimizedAndHiddenDespiteOffScreen() {
        // Minimized/hidden windows have no on-screen entry but still belong to the session.
        #expect(WindowEnumerator.keepAfterFilters(
            isMinimized: true, isHidden: false, isOnScreen: false,
            includeMinimized: true, includeHidden: true, currentSpaceOnly: true))
        #expect(WindowEnumerator.keepAfterFilters(
            isMinimized: false, isHidden: true, isOnScreen: false,
            includeMinimized: true, includeHidden: true, currentSpaceOnly: true))
    }

}
