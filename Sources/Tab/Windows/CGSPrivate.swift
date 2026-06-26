import CoreGraphics
import Foundation

// Private SkyLight (CGS) functions. There is no public API for cross-Space window
// state or for telling a real window apart from a phantom (a closed/orderOut'd/
// alpha=0 window that lingers in CGWindowListCopyWindowInfo). We link the symbols
// directly.

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: UInt32) -> CFArray

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(
    _ cid: UInt32, _ owner: Int, _ spaces: CFArray, _ options: Int,
    _ setTags: UnsafeMutablePointer<Int>, _ clearTags: UnsafeMutablePointer<Int>
) -> CFArray

enum CGS {
    /// CGWindowIDs of every *real* window across all Spaces, per the window server.
    /// Excludes "invisible"-tagged windows — phantoms (closed-but-not-yet-evicted,
    /// alpha=0, orderOut'd) and inactive tabs — which still appear in
    /// `CGWindowListCopyWindowInfo` but aren't real windows. Returns an empty set if
    /// the query fails, which callers treat as "don't filter".
    static func visibleWindowIDsAcrossAllSpaces() -> Set<CGWindowID> {
        let cid = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [NSDictionary] else { return [] }

        var spaceIDs: [UInt64] = []
        for display in displays {
            guard let spaces = display["Spaces"] as? [NSDictionary] else { continue }
            for space in spaces {
                if let id = space["id64"] as? UInt64 { spaceIDs.append(id) }
            }
        }
        guard !spaceIDs.isEmpty else { return [] }

        let screenSaverLevel1000 = 1 << 1   // options without the .invisible bits
        var setTags = 0
        var clearTags = 0
        guard let wids = CGSCopyWindowsWithOptionsAndTags(
            cid, 0, spaceIDs as CFArray, screenSaverLevel1000, &setTags, &clearTags
        ) as? [CGWindowID] else {
            return []
        }
        return Set(wids)
    }
}
