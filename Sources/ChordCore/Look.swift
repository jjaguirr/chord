/// A monitor's usable area (visible frame) in the same coordinate space as the window
/// rects handed to the picker.
public struct PickerMonitor: Equatable, Sendable {
    public let id: Int
    public let bounds: PickerRect
    public let isPrimary: Bool
    public init(id: Int, bounds: PickerRect, isPrimary: Bool = false) {
        self.id = id
        self.bounds = bounds
        self.isPrimary = isPrimary
    }
}

extension PickDirection {
    /// The hjkl keys that make this direction: `l`, `h`, `k`, `j`, or a chord such as `h+j`.
    public var keys: String {
        let parts = [x < 0 ? "h" : (x > 0 ? "l" : nil), y < 0 ? "k" : (y > 0 ? "j" : nil)]
        return parts.compactMap { $0 }.joined(separator: "+")
    }
}

/// What a Look press decided, with enough detail to log why.
public struct LookDecision: Equatable, Sendable {
    /// Where the target was found.
    public enum Scope: Equatable, Sendable {
        case sameMonitor
        case adjacentMonitor
    }

    /// Why nothing was picked.
    public enum Miss: Equatable, Sendable {
        case noDirection
        case originNotVisible
        case noOtherWindow
        /// Nothing in that direction on this monitor, and no monitor lies that way.
        case noMonitorInDirection
        /// A monitor lies that way but shows no window.
        case neighbourMonitorEmpty
        /// A monitor lies that way, but the Picker accepted none of its windows.
        case neighbourHasNoTarget
    }

    public enum Outcome: Equatable, Sendable {
        case picked(Int, Scope)
        case nothing(Miss)
    }

    public let outcome: Outcome
    /// Window ids (origin excluded) offered to the Picker in the pass that decided.
    public let candidates: [Int]

    public var target: Int? {
        if case .picked(let id, _) = outcome { return id }
        return nil
    }

    public var summary: String {
        switch outcome {
        case .picked(let id, .sameMonitor): return "picked window \(id) on the same monitor"
        case .picked(let id, .adjacentMonitor): return "picked window \(id) on the adjacent monitor"
        case .nothing(.noDirection): return "no direction"
        case .nothing(.originNotVisible): return "the focused window is not among the visible windows"
        case .nothing(.noOtherWindow): return "no other visible window"
        case .nothing(.noMonitorInDirection):
            return "nothing that way on this monitor and no monitor that way"
        case .nothing(.neighbourMonitorEmpty):
            return "nothing that way on this monitor; the monitor that way shows no window"
        case .nothing(.neighbourHasNoTarget):
            return "nothing that way on this monitor; the monitor that way has no eligible window"
        }
    }
}

/// Look: the nearest window in a direction, crossing to the adjacent monitor at a monitor
/// edge. Pure; the ranking is the `Picker`'s, run on a candidate pool chosen as follows.
///
/// 1. The pool is the windows on the focused window's monitor (a window belongs to the
///    monitor holding its center, else the primary monitor, else the first).
/// 2. If the Picker finds nothing there, the monitor is "at its edge": the pool becomes the
///    windows on monitors that lie beyond that edge in the direction (entirely past the
///    edge and overlapping the monitor's extent on the other axis, so a diagonal-only
///    neighbour is not adjacent; a chord counts either axis), plus the focused window.
///    The Picker then picks the nearest of those. A nearer window on the adjacent monitor
///    never beats a window on the same monitor.
///
/// Ties inside a pool are the Picker's, in order: 16-point score buckets (beam gap for
/// h/j/k/l with at least 25% overlap, else distance along plus twice the offset across),
/// same layer as the focused window, most recently used, smaller offset across, a window
/// whose facing corner is nearer the pool's screen corner (chords only; the bounds are the
/// focused monitor's in step 1, the union of the pool's monitors in step 2), lowest id.
/// `cameFrom` wins an exact score tie, so a press followed by its opposite returns to where
/// you were. The Picker also drops a target that would not pick the focused window back
/// from the opposite key. With no monitors, every window is one pool.
public enum Look {
    public static func decide(
        from originID: Int, direction: PickDirection, cameFrom: Int? = nil,
        windows: [PickerWindow], monitors: [PickerMonitor]
    ) -> LookDecision {
        guard direction.x != 0 || direction.y != 0 else { return miss(.noDirection) }
        guard let origin = windows.first(where: { $0.id == originID }) else {
            return miss(.originNotVisible)
        }
        guard windows.contains(where: { $0.id != originID }) else { return miss(.noOtherWindow) }

        guard !monitors.isEmpty else {
            let others = windows.filter { $0.id != originID }.map(\.id)
            let bounds = union(windows.map(\.rect))
            return result(
                Picker.pick(
                    from: originID, direction: direction, cameFrom: cameFrom, windows: windows,
                    screenBounds: bounds), .sameMonitor, others, otherwise: .noMonitorInDirection)
        }

        let originMonitor = monitors[MonitorAdjacency.index(holding: origin.rect, in: monitors)]
        let held = windows.map { (window: $0, monitor: MonitorAdjacency.index(holding: $0.rect, in: monitors)) }
        let here = held.filter { monitors[$0.monitor] == originMonitor }.map(\.window)
        let hereOthers = here.filter { $0.id != originID }.map(\.id)
        if let target = Picker.pick(
            from: originID, direction: direction, cameFrom: cameFrom, windows: here,
            screenBounds: originMonitor.bounds)
        {
            return LookDecision(outcome: .picked(target, .sameMonitor), candidates: hereOthers)
        }

        let neighbours = monitors.filter {
            $0 != originMonitor && MonitorAdjacency.isBeyond($0.bounds, originMonitor.bounds, direction)
        }
        guard !neighbours.isEmpty else {
            return LookDecision(outcome: .nothing(.noMonitorInDirection), candidates: hereOthers)
        }
        let beyond = held.filter { entry in neighbours.contains(monitors[entry.monitor]) }.map(\.window)
        guard !beyond.isEmpty else {
            return LookDecision(outcome: .nothing(.neighbourMonitorEmpty), candidates: [])
        }
        let pool = [origin] + beyond
        let bounds = union(([originMonitor] + neighbours).map(\.bounds))
        return result(
            Picker.pick(
                from: originID, direction: direction, cameFrom: cameFrom, windows: pool,
                screenBounds: bounds), .adjacentMonitor, beyond.map(\.id),
            otherwise: .neighbourHasNoTarget)
    }

    private static func miss(_ miss: LookDecision.Miss) -> LookDecision {
        LookDecision(outcome: .nothing(miss), candidates: [])
    }

    private static func result(
        _ target: Int?, _ scope: LookDecision.Scope, _ candidates: [Int],
        otherwise: LookDecision.Miss
    ) -> LookDecision {
        LookDecision(
            outcome: target.map { .picked($0, scope) } ?? .nothing(otherwise), candidates: candidates)
    }

    private static func union(_ rects: [PickerRect]) -> PickerRect {
        guard let first = rects.first else { return PickerRect(x: 0, y: 0, width: 0, height: 0) }
        var left = first.x
        var top = first.y
        var right = first.x + first.width
        var bottom = first.y + first.height
        for rect in rects.dropFirst() {
            left = min(left, rect.x)
            top = min(top, rect.y)
            right = max(right, rect.x + rect.width)
            bottom = max(bottom, rect.y + rect.height)
        }
        return PickerRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
