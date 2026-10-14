/// Physical key positions interpreted by the pure key state machine.
public enum ChordKey: Hashable, Sendable { case h, j, k, l, zero, escape }

public struct KeyModifiers: Equatable, Sendable {
    public var control: Bool
    public var shift: Bool
    public var mod: Bool
    public init(control: Bool = false, shift: Bool = false, mod: Bool = false) {
        self.control = control
        self.shift = shift
        self.mod = mod
    }
}

public enum KeyInput: Equatable, Sendable {
    case down(ChordKey, repeat: Bool, modifiers: KeyModifiers)
    case up(ChordKey, modifiers: KeyModifiers)
}

public enum KeyIntent: Equatable, Sendable {
    case look(PickDirection)
    case carry(dx: Double, dy: Double)
    case reshape(aspectDelta: Double, areaDelta: Double)
    case unfold
    case spread
    case abortCharge
}

/// Events and monotonic timestamps in; pure intents out. Call `advance` from the
/// event loop's timer so holds and held-direction repeats do not depend on key-up.
public struct KeyStateMachine: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var holdThreshold: Double
        public var chordWindow: Double
        public var repeatStages: [Double]
        public var magnetDistance: Double
        public init(
            holdThreshold: Double = 0.7, chordWindow: Double = 0.035,
            repeatStages: [Double] = [10, 20, 30], magnetDistance: Double = 30
        ) {
            self.holdThreshold = holdThreshold
            self.chordWindow = chordWindow
            self.repeatStages = repeatStages
            self.magnetDistance = magnetDistance
        }
    }

    private static let tapThreshold = 0.25
    private static let repeatInterval = 0.1
    private static let reshapeStep = 0.05

    public struct Edges: Equatable, Sendable {
        public let left: Double
        public let right: Double
        public let top: Double
        public let bottom: Double
        public init(left: Double, right: Double, top: Double, bottom: Double) {
            self.left = left; self.right = right; self.top = top; self.bottom = bottom
        }
    }


    public let configuration: Configuration
    private var downKeys: Set<ChordKey> = []
    private var chargeStarted: Double?
    private var spreadStarted = false
    private var pendingDirection: (key: ChordKey, at: Double)?
    private var carryKeys: Set<ChordKey> = []
    private var carryNextAt: Double?
    private var carryTicks = 0

    public init(configuration: Configuration = Configuration()) { self.configuration = configuration }

    public mutating func process(
        _ input: KeyInput, at time: Double, rect: PickerRect, edges: Edges
    ) -> [KeyIntent] {
        switch input {
        case let .down(key, isRepeat, modifiers):
            guard !isRepeat, downKeys.insert(key).inserted else { return [] }
            if key == .zero {
                guard modifiers.mod else { return [] }
                chargeStarted = time; spreadStarted = false; return []
            }
            if key == .escape, chargeStarted != nil {
                chargeStarted = nil; spreadStarted = false
                return [.abortCharge]
            }
            guard direction(key) != nil else { return [] }
            if modifiers.control {
                let (aspect, area) = reshapeDeltas(for: key)
                return [.reshape(aspectDelta: aspect, areaDelta: area)]
            }
            if modifiers.shift {
                carryKeys.insert(key); carryTicks = 1
                carryNextAt = time + Self.repeatInterval
                if let intent = carryIntent(vector: carryVector, ticks: 0, rect: rect, edges: edges) {
                    return [intent]
                }
                return []
            }
            if let pending = pendingDirection, time - pending.at <= configuration.chordWindow,
               let combined = chord(pending.key, key) {
                pendingDirection = nil
                if combined.x == 0 && combined.y == 0 { return [] }
                return [.look(combined)]
            }
            var result: [KeyIntent] = []
            if let pendingDirection, let old = direction(pendingDirection.key) {
                result.append(.look(old))
            }
            pendingDirection = (key, time)
            return result
        case let .up(key, _):
            guard downKeys.remove(key) != nil else { return [] }
            if key == .zero, let started = chargeStarted {
                chargeStarted = nil
                if !spreadStarted && time - started >= configuration.holdThreshold {
                    spreadStarted = true
                    return [.spread]
                }
                return !spreadStarted && time - started <= Self.tapThreshold ? [.unfold] : []
            }
            if carryKeys.remove(key) != nil, carryKeys.isEmpty { carryNextAt = nil }
            if let pendingDirection, pendingDirection.key == key {
                self.pendingDirection = nil
                if let vector = direction(key) { return [.look(vector)] }
            }
            return []
        }
    }

    public mutating func advance(to time: Double, rect: PickerRect, edges: Edges) -> [KeyIntent] {
        var result: [KeyIntent] = []
        if let started = chargeStarted, !spreadStarted,
           time - started >= configuration.holdThreshold {
            spreadStarted = true
            result.append(.spread)
        }
        if let pendingDirection, time - pendingDirection.at > configuration.chordWindow {
            self.pendingDirection = nil
            if let vector = direction(pendingDirection.key) { result.append(.look(vector)) }
        }
        if !carryKeys.isEmpty, let next = carryNextAt, time >= next || time.nextUp >= next {
            if let intent = carryIntent(vector: carryVector, ticks: carryTicks, rect: rect, edges: edges) {
                result.append(intent)
            }
            carryTicks += 1
            carryNextAt = next + Self.repeatInterval
        }
        return result
    }

    /// Edge magnets snap each directed axis independently, leaving the other axis
    /// unchanged. `ticks` selects the configured 10/20/30 (then capped) ramp.
    public func carry(vector: PickDirection, ticks: Int, rect: PickerRect, edges: Edges) -> (dx: Double, dy: Double) {
        let distance = stageDistance(ticks)
        var dx = Double(vector.x) * distance
        var dy = Double(vector.y) * distance
        if vector.x < 0 && abs(rect.x - edges.left) <= configuration.magnetDistance { dx = edges.left - rect.x }
        if vector.x > 0 && abs(edges.right - rect.x - rect.width) <= configuration.magnetDistance { dx = edges.right - rect.x - rect.width }
        if vector.y < 0 && abs(rect.y - edges.top) <= configuration.magnetDistance { dy = edges.top - rect.y }
        if vector.y > 0 && abs(edges.bottom - rect.y - rect.height) <= configuration.magnetDistance { dy = edges.bottom - rect.y - rect.height }
        return (dx, dy)
    }

    /// Deltas are applied to log(width/height) and log(width*height), respectively.
    public func reshapeDeltas(for key: ChordKey) -> (aspect: Double, area: Double) {
        switch key {
        case .h: (-Self.reshapeStep, 0)
        case .l: (Self.reshapeStep, 0)
        case .j: (0, Self.reshapeStep)
        case .k: (0, -Self.reshapeStep)
        default: (0, 0)
        }
    }

    private func stageDistance(_ ticks: Int) -> Double {
        guard !configuration.repeatStages.isEmpty else { return 0 }
        return configuration.repeatStages[max(0, min(ticks, configuration.repeatStages.count - 1))]
    }
    private var carryVector: PickDirection {
        carryKeys.reduce(into: PickDirection(x: 0, y: 0)) { vector, key in
            guard let direction = direction(key) else { return }
            vector = PickDirection(x: vector.x + direction.x, y: vector.y + direction.y)
        }
    }
    private func carryIntent(vector: PickDirection, ticks: Int, rect: PickerRect, edges: Edges) -> KeyIntent? {
        guard vector.x != 0 || vector.y != 0 else { return nil }
        let delta = carry(vector: vector, ticks: ticks, rect: rect, edges: edges)
        return .carry(dx: delta.dx, dy: delta.dy)
    }
    private func direction(_ key: ChordKey) -> PickDirection? {
        switch key { case .h: .h; case .j: .j; case .k: .k; case .l: .l; default: nil }
    }
    private func chord(_ first: ChordKey, _ second: ChordKey) -> PickDirection? {
        guard let a = direction(first), let b = direction(second) else { return nil }
        return PickDirection(x: a.x + b.x, y: a.y + b.y)
    }
}
