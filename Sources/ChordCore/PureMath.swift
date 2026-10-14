// Stdlib-only exp, log and pow for ChordCore. The core may not import
// Foundation or any OS module, and the Swift standard library has no
// transcendental functions, so they are computed here. Accuracy is ~1e-15
// relative over the ranges frame() uses.

/// atanh(s) for 0 <= s <= 1/3, as a power series.
private func atanhSeries(_ s: Double) -> Double {
    let s2 = s * s
    var power = s
    var sum = 0.0
    var k = 0.0
    while true {
        let term = power / (2 * k + 1)
        sum += term
        if abs(term) < 1e-17 * abs(sum) || term == 0 { break }
        power *= s2
        k += 1
    }
    return sum
}

/// ln 2 = 2 * atanh(1/3).
private let naturalLogOfTwo = 2 * atanhSeries(1.0 / 3.0)

/// Natural logarithm for finite x > 0.
func naturalLog(_ x: Double) -> Double {
    precondition(x > 0 && x.isFinite, "naturalLog requires a finite positive value")
    let m = x.significand            // in [1, 2)
    let e = x.exponent               // x = m * 2^e
    // ln m = 2 * atanh((m - 1) / (m + 1)), with the argument in [0, 1/3).
    return Double(e) * naturalLogOfTwo + 2 * atanhSeries((m - 1) / (m + 1))
}

/// e^y for moderate finite y (|y| well below the overflow range).
func naturalExp(_ y: Double) -> Double {
    precondition(y.isFinite, "naturalExp requires a finite value")
    // y = k ln2 + r with |r| <= ln2 / 2, then e^y = 2^k * e^r.
    let k = (y / naturalLogOfTwo).rounded()
    let r = y - k * naturalLogOfTwo
    var term = 1.0
    var sum = 1.0
    for n in 1...30 {
        term *= r / Double(n)
        sum += term
    }
    return Double(sign: .plus, exponent: Int(k), significand: sum)
}

/// base^exponent for finite base > 0 and finite exponent.
func positivePow(_ base: Double, _ exponent: Double) -> Double {
    naturalExp(exponent * naturalLog(base))
}
