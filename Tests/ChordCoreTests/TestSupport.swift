import Testing

/// Deterministic generator so random-sample tests replay identically.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

func expectRelativelyClose(
    _ actual: Double,
    _ expected: Double,
    relTol: Double,
    _ message: String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let scale = max(abs(expected), 1e-300)
    #expect(
        abs(actual - expected) / scale <= relTol,
        "\(message) actual=\(actual) expected=\(expected)",
        sourceLocation: sourceLocation
    )
}
