/// Rectangle used by the pure spatial picker.
public struct PickerRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    fileprivate var centerX: Double { x + width / 2 }
    fileprivate var centerY: Double { y + height / 2 }
}

/// A window snapshot. Inactive stack members are omitted during normalization.
public struct PickerWindow: Equatable, Sendable {
    public let id: Int
    public let rect: PickerRect
    public let layer: Int
    public let mru: Int
    public let coverage: Double
    public let minimized: Bool
    public let onWorkspace: Bool
    public let stack: Int?
    public let activeInStack: Bool
    public init(id: Int, rect: PickerRect, layer: Int, mru: Int, coverage: Double,
                minimized: Bool = false, onWorkspace: Bool = true, stack: Int? = nil,
                activeInStack: Bool = true) {
        self.id = id; self.rect = rect; self.layer = layer; self.mru = mru
        self.coverage = coverage; self.minimized = minimized; self.onWorkspace = onWorkspace
        self.stack = stack; self.activeInStack = activeInStack
    }
}

public struct PickDirection: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public var opposite: PickDirection { PickDirection(x: -x, y: -y) }
    public static let h = PickDirection(x: -1, y: 0)
    public static let l = PickDirection(x: 1, y: 0)
    public static let k = PickDirection(x: 0, y: -1)
    public static let j = PickDirection(x: 0, y: 1)
}

/// Reversibility is preferred only on exact primary-score ties; pathological layouts
/// can remain non-reciprocal under the required tie order. Horizontal z-fallback is a no-op.
public enum Picker {
    private static let grid = 8.0
    private static func snapped(_ value: Double) -> Double { (value / grid).rounded() * grid }
    private static func snapped(_ rect: PickerRect) -> PickerRect {
        let left = snapped(rect.x), top = snapped(rect.y)
        let right = snapped(rect.x + rect.width), bottom = snapped(rect.y + rect.height)
        return PickerRect(x: left, y: top, width: right - left, height: bottom - top)
    }
    private struct Candidate {
        let window: PickerWindow
        let along: Double
        let perpendicular: Double
        let gap: Double
        let overlap: Double
        let facingTie: Double
    }

    /// Returns nil for a reserved cancel chord or when no directional target exists.
    public static func pick(from originID: Int, direction: PickDirection,
                            cameFrom: Int? = nil, windows: [PickerWindow], screenBounds: PickerRect) -> Int? {
        choose(from: originID, direction: direction, cameFrom: cameFrom, windows: windows,
               screenBounds: screenBounds, reciprocal: true)
    }

    private static func choose(from originID: Int, direction: PickDirection, cameFrom: Int?,
                               windows: [PickerWindow], screenBounds: PickerRect,
                               reciprocal: Bool) -> Int? {
        guard direction.x != 0 || direction.y != 0 else { return nil }
        let normalized = windows.map { w in
            PickerWindow(id: w.id, rect: snapped(w.rect), layer: w.layer, mru: w.mru,
                         coverage: w.coverage, minimized: w.minimized, onWorkspace: w.onWorkspace,
                         stack: w.stack, activeInStack: w.activeInStack)
        }.filter { !$0.minimized && $0.onWorkspace && ($0.stack == nil || $0.activeInStack) }
        guard let origin = normalized.first(where: { $0.id == originID }) else { return nil }
        let ox = origin.rect.centerX, oy = origin.rect.centerY
        let straight = direction.x == 0 || direction.y == 0
        var candidates: [Candidate] = []
        for w in normalized where w.id != originID && w.coverage < 0.8 {
            let dx = w.rect.centerX - ox, dy = w.rect.centerY - oy
            let dot = dx * Double(direction.x) + dy * Double(direction.y)
            guard dot > 8 else { continue }
            let length = (Double(direction.x * direction.x + direction.y * direction.y)).squareRoot()
            let along = dot / length
            let perpendicular = abs(dx * Double(direction.y) - dy * Double(direction.x)) / length
            let horizontal = direction.y == 0
            let extent = min(horizontal ? origin.rect.height : origin.rect.width,
                             horizontal ? w.rect.height : w.rect.width)
            let intersection = horizontal
                ? max(0, min(origin.rect.y + origin.rect.height, w.rect.y + w.rect.height) - max(origin.rect.y, w.rect.y))
                : max(0, min(origin.rect.x + origin.rect.width, w.rect.x + w.rect.width) - max(origin.rect.x, w.rect.x))
            let overlap = extent > 0 ? intersection / extent : 0
            let gap = max(0, along - (horizontal ? origin.rect.width + w.rect.width : origin.rect.height + w.rect.height) / 2)
            let fx = direction.x > 0 ? w.rect.x + w.rect.width : w.rect.x
            let fy = direction.y > 0 ? w.rect.y + w.rect.height : w.rect.y
            let sx = direction.x > 0 ? screenBounds.x + screenBounds.width : screenBounds.x
            let sy = direction.y > 0 ? screenBounds.y + screenBounds.height : screenBounds.y
            candidates.append(Candidate(window: w, along: along, perpendicular: perpendicular, gap: gap,
                                        overlap: overlap, facingTie: straight ? 0 : ((fx - sx) * (fx - sx) + (fy - sy) * (fy - sy)).squareRoot()))
        }
        func score(_ c: Candidate, beam: Bool) -> Double { beam ? c.gap : c.along + 2 * c.perpendicular }
        func baseOrder(_ a: Candidate, _ b: Candidate, beam: Bool) -> Bool {
            let ascore = Int((score(a, beam: beam) / 16).rounded(.down))
            let bscore = Int((score(b, beam: beam) / 16).rounded(.down))
            if ascore != bscore { return ascore < bscore }
            if (a.window.layer == origin.layer) != (b.window.layer == origin.layer) { return a.window.layer == origin.layer }
            if a.window.mru != b.window.mru { return a.window.mru > b.window.mru }
            if a.perpendicular != b.perpendicular { return a.perpendicular < b.perpendicular }
            if !straight && a.facingTie != b.facingTie { return a.facingTie < b.facingTie }
            return a.window.id < b.window.id
        }
        func ranked(_ pool: [Candidate], beam: Bool) -> Candidate? {
            guard let best = pool.min(by: { baseOrder($0, $1, beam: beam) }) else { return nil }
            guard let cameFrom,
                  let preferred = pool.first(where: { $0.window.id == cameFrom }),
                  score(preferred, beam: beam) == score(best, beam: beam),
                  (preferred.window.layer == origin.layer) == (best.window.layer == origin.layer) else {
                return best
            }
            return preferred
        }
        if candidates.isEmpty {
            let target = zFallback(origin: origin, direction: direction, windows: normalized)
            guard reciprocal, let target else { return target }
            return choose(from: target, direction: direction.opposite, cameFrom: originID,
                          windows: windows, screenBounds: screenBounds, reciprocal: false) == originID ? target : nil
        }
        let beamCandidates = straight ? candidates.filter { $0.overlap >= 0.25 } : []
        let tiers: [([Candidate], Bool)] = beamCandidates.isEmpty
            ? [(candidates, false)] : [(beamCandidates, true), (candidates.filter { $0.overlap < 0.25 }, false)]
        for (pool, beam) in tiers where !pool.isEmpty {
            guard let target = ranked(pool, beam: beam) else { continue }
            if !reciprocal { return target.window.id }
            if choose(from: target.window.id, direction: direction.opposite, cameFrom: originID,
                      windows: windows, screenBounds: screenBounds, reciprocal: false) == originID {
                return target.window.id
            }
        }
        return tiers.compactMap { pool, beam in ranked(pool, beam: beam)?.window.id }.first
    }

    private static func zFallback(origin: PickerWindow, direction: PickDirection,
                                  windows: [PickerWindow]) -> Int? {
        if direction == .k {
            return windows.filter { $0.layer == 1 && $0.id != origin.id }.sorted {
                let a = overlapArea(origin.rect, $0.rect), b = overlapArea(origin.rect, $1.rect)
                if a != b { return a > b }
                if $0.mru != $1.mru { return $0.mru > $1.mru }
                return $0.id < $1.id
            }.first?.id
        }
        if direction == .j {
            let tiles = windows.filter { $0.layer == 0 && $0.id != origin.id }
            let under = tiles.filter {
                origin.rect.centerX >= $0.rect.x && origin.rect.centerX <= $0.rect.x + $0.rect.width &&
                origin.rect.centerY >= $0.rect.y && origin.rect.centerY <= $0.rect.y + $0.rect.height
            }
            return (under.isEmpty ? tiles : under).sorted {
                if $0.mru != $1.mru { return $0.mru > $1.mru }
                return $0.id < $1.id
            }.first?.id
        }
        return nil
    }

    private static func overlapArea(_ a: PickerRect, _ b: PickerRect) -> Double {
        max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x)) *
        max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
    }
}
