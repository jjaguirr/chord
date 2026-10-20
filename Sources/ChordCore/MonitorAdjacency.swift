/// Which monitor lies past which edge, and where a carried window lands there. Pure; the
/// one adjacency rule shared by Look (focus crossing) and cross-monitor carry. Rects are
/// monitor visible frames in one top-left, y-down space of points, so monitors of
/// different size or scale compare directly.
public enum MonitorAdjacency {
    /// The monitor holding the rect's center (half-open, as `ScreenGeometry` reads it), else
    /// the primary monitor, else the first. `monitors` must not be empty.
    public static func index(holding rect: PickerRect, in monitors: [PickerMonitor]) -> Int {
        let cx = rect.x + rect.width / 2
        let cy = rect.y + rect.height / 2
        if let held = monitors.firstIndex(where: {
            $0.bounds.x <= cx && cx < $0.bounds.x + $0.bounds.width
                && $0.bounds.y <= cy && cy < $0.bounds.y + $0.bounds.height
        }) {
            return held
        }
        return monitors.firstIndex(where: \.isPrimary) ?? 0
    }

    /// `other` lies past `origin`'s edge in a direction the press asks for, and shares
    /// some extent with it on the other axis. One point of slack absorbs rounding.
    public static func isBeyond(_ other: PickerRect, _ origin: PickerRect, _ direction: PickDirection) -> Bool {
        let slack = 1.0
        func shares(_ aLow: Double, _ aSize: Double, _ bLow: Double, _ bSize: Double) -> Bool {
            min(aLow + aSize, bLow + bSize) - max(aLow, bLow) > 0
        }
        let sharesRows = shares(origin.y, origin.height, other.y, other.height)
        let sharesColumns = shares(origin.x, origin.width, other.x, other.width)
        if direction.x > 0, other.x >= origin.x + origin.width - slack, sharesRows { return true }
        if direction.x < 0, other.x + other.width <= origin.x + slack, sharesRows { return true }
        if direction.y > 0, other.y >= origin.y + origin.height - slack, sharesColumns { return true }
        if direction.y < 0, other.y + other.height <= origin.y + slack, sharesColumns { return true }
        return false
    }

    /// The monitor a window held by `origin` crosses to in `direction`: among the monitors
    /// beyond `origin`'s edge, the nearest (smallest gap along the press), then the one
    /// sharing the most extent across it, then the first listed. Nil when none lies that way.
    public static func neighbour(
        of origin: PickerMonitor, in monitors: [PickerMonitor], direction: PickDirection
    ) -> PickerMonitor? {
        func gap(_ other: PickerMonitor) -> Double {
            var total = 0.0
            let o = origin.bounds
            let b = other.bounds
            if direction.x > 0 { total += max(0, b.x - (o.x + o.width)) }
            if direction.x < 0 { total += max(0, o.x - (b.x + b.width)) }
            if direction.y > 0 { total += max(0, b.y - (o.y + o.height)) }
            if direction.y < 0 { total += max(0, o.y - (b.y + b.height)) }
            return total
        }
        func shared(_ other: PickerMonitor) -> Double {
            let o = origin.bounds
            let b = other.bounds
            var total = 0.0
            if direction.x != 0 { total += max(0, min(o.y + o.height, b.y + b.height) - max(o.y, b.y)) }
            if direction.y != 0 { total += max(0, min(o.x + o.width, b.x + b.width) - max(o.x, b.x)) }
            return total
        }
        let candidates = monitors.enumerated().filter {
            $0.element != origin && isBeyond($0.element.bounds, origin.bounds, direction)
        }
        return candidates.min { a, b in
            let (ga, gb) = (gap(a.element), gap(b.element))
            if ga != gb { return ga < gb }
            let (sa, sb) = (shared(a.element), shared(b.element))
            if sa != sb { return sa > sb }
            return a.offset < b.offset
        }?.element
    }

    /// Where a window held by `origin` lands on `target` after a carry in `direction`: the
    /// same size, flush with the edge it enters through on each pressed axis along which
    /// `target` really lies beyond `origin`, and its position on any other axis kept,
    /// clamped into `target`. A window larger than `target` cannot fit with its size kept;
    /// it is aligned to the target's top-left corner instead.
    public static func landing(
        of window: PickerRect, from origin: PickerRect, on target: PickerRect, direction: PickDirection
    ) -> PickerRect {
        func place(_ position: Double, _ size: Double, _ low: Double, _ extent: Double, _ step: Int) -> Double {
            if step > 0 { return low }
            if step < 0 { return max(low, low + extent - size) }
            return max(low, min(position, low + extent - size))
        }
        let stepX = isBeyond(target, origin, PickDirection(x: direction.x, y: 0)) ? direction.x : 0
        let stepY = isBeyond(target, origin, PickDirection(x: 0, y: direction.y)) ? direction.y : 0
        return PickerRect(
            x: place(window.x, window.width, target.x, target.width, stepX),
            y: place(window.y, window.height, target.y, target.height, stepY),
            width: window.width, height: window.height)
    }
}
