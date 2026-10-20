import ChordCore
import CoreGraphics
import Foundation

/// Reads window frames from the window server. AeroSpace reports no geometry, and
/// its window ids are the system's window numbers, so the two line up by number.
/// Reads only; needs no permission (titles would, and are never read).
///
/// Coordinates are top-left screen points, the same space the Accessibility backend
/// and `ScreenGeometry` use.
enum WindowFrameReader {
    /// Frames of the windows in `ids` that the window server lists. A window it does
    /// not list is absent from the result; the caller never gets a guessed frame.
    static func frames(of ids: [WindowID]) -> [WindowID: ScreenRect] {
        let wanted = Set(ids.map(\.rawValue))
        guard !wanted.isEmpty,
            let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var result: [WindowID: ScreenRect] = [:]
        for entry in list {
            guard let number = entry[kCGWindowNumber as String] as? Int, wanted.contains(number),
                let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: dictionary)
            else { continue }
            result[WindowID(number)] = ScreenRect(
                x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
        }
        return result
    }
}
