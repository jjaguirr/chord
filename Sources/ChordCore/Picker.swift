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

/// A window snapshot. `stack` identifies a stack; `activeInStack` selects its
/// representative. Inactive stack members are omitted during normalization.
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
    public let monitor: Int

    public init(id: Int, rect: PickerRect, layer: Int, mru: Int, coverage: Double,
                minimized: Bool = false, onWorkspace: Bool = true, stack: Int? = nil,
                activeInStack: Bool = true, monitor: Int = 0) {
        self.id = id; self.rect = rect; self.layer = layer; self.mru = mru
        self.coverage = coverage; self.minimized = minimized; self.onWorkspace = onWorkspace
        self.stack = stack; self.activeInStack = activeInStack; self.monitor = monitor
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
                            windows: [PickerWindow]) -> Int? {
        guard direction.x != 0 || direction.y != 0,
              let originIndex = windows.firstIndex(where: { $0.id == originID }) else { return nil }
        let snappedWindows = windows.map { window in
            PickerWindow(id: window.id, rect: snapped(window.rect), layer: window.layer,
                         mru: window.mru, coverage: window.coverage, minimized: window.minimized,
                         onWorkspace: window.onWorkspace, stack: window.stack,
                         activeInStack: window.activeInStack, monitor: window.monitor)
        }
        let origin = snappedWindows[originIndex]
        let normalized = snappedWindows.filter { w in
            !w.minimized && w.onWorkspace && (w.stack == nil || w.activeInStack)
        }
        let ox = origin.rect.centerX, oy = origin.rect.centerY
        var candidates: [Candidate] = []
        for w in normalized where w.id != originID && w.coverage < 0.8 {
            let dx = w.rect.centerX - ox, dy = w.rect.centerY - oy
            let dot = dx * Double(direction.x) + dy * Double(direction.y)
            guard dot > 8 else { continue }
            let length = (Double(direction.x * direction.x + direction.y * direction.y)).squareRoot()
            let along = dot / length
            let perpendicular = abs(dx * Double(direction.y) - dy * Double(direction.x)) / length
            let horizontal = direction.y == 0
            let originExtent = horizontal ? origin.rect.height : origin.rect.width
            let candidateExtent = horizontal ? w.rect.height : w.rect.width
            let extent = min(originExtent, candidateExtent)
            let intersection = horizontal
                ? max(0, min(origin.rect.y + origin.rect.height, w.rect.y + w.rect.height) - max(origin.rect.y, w.rect.y))
                : max(0, min(origin.rect.x + origin.rect.width, w.rect.x + w.rect.width) - max(origin.rect.x, w.rect.x))
            let overlapRatio = extent > 0 ? intersection / extent : 0
            let gap = max(0, along - (horizontal ? origin.rect.width + w.rect.width : origin.rect.height + w.rect.height) / 2)
            let facing = abs(dx) + abs(dy)
            candidates.append(Candidate(window: w, along: along, perpendicular: perpendicular,
                                        gap: gap, overlap: overlapRatio, facingTie: facing))
        }
        guard !candidates.isEmpty else { return zFallback(origin: origin, direction: direction, windows: normalized) }

        let straight = direction.x == 0 || direction.y == 0
        let beam = straight ? candidates.filter { $0.overlap >= 0.25 } : []
        let pool = beam.isEmpty ? candidates : beam
        func ordered(_ a: Candidate, _ b: Candidate) -> Bool {
            let ascore = beam.isEmpty ? a.along + 2 * a.perpendicular : a.gap
            let bscore = beam.isEmpty ? b.along + 2 * b.perpendicular : b.gap
            let ab = Int((ascore / 16).rounded(.down)), bb = Int((bscore / 16).rounded(.down))
            if ab != bb { return ab < bb }
            if (a.window.layer == origin.layer) != (b.window.layer == origin.layer) { return a.window.layer == origin.layer }
            if a.window.mru != b.window.mru { return a.window.mru > b.window.mru }
            if a.perpendicular != b.perpendicular { return a.perpendicular < b.perpendicular }
            if straight == false && a.facingTie != b.facingTie { return a.facingTie < b.facingTie }
            return a.window.id < b.window.id
        }
        return pool.sorted(by: ordered).first?.window.id
    }

    private static func zFallback(origin: PickerWindow, direction: PickDirection,
                                  windows: [PickerWindow]) -> Int? {
        if direction == .k {
            return windows.filter { $0.layer == 1 && $0.id != origin.id }
                .sorted { overlapArea(origin.rect, $0.rect) == overlapArea(origin.rect, $1.rect) ? $0.mru > $1.mru : overlapArea(origin.rect, $0.rect) > overlapArea(origin.rect, $1.rect) }.first?.id
        }
        if direction == .j {
            let under = windows.filter { $0.layer == 0 && $0.id != origin.id &&
                origin.rect.centerX >= $0.rect.x && origin.rect.centerX <= $0.rect.x + $0.rect.width &&
                origin.rect.centerY >= $0.rect.y && origin.rect.centerY <= $0.rect.y + $0.rect.height }
            return under.sorted { $0.mru > $1.mru }.first?.id ?? windows.filter { $0.layer == 0 && $0.id != origin.id }.sorted { $0.mru > $1.mru }.first?.id
        }
        return nil
    }

    private static func overlapArea(_ a: PickerRect, _ b: PickerRect) -> Double {
        max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x)) *
        max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
    }
}
