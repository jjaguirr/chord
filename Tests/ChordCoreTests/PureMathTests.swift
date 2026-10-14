import Foundation
import Testing
@testable import ChordCore

/// Foundation is imported here only as an oracle. ChordCore itself is stdlib-only.
@Suite("stdlib exp/log/pow")
struct PureMathTests {
    @Test func naturalLogMatchesFoundation() {
        var rng = SplitMix64(state: 11)
        for _ in 0..<2_000 {
            let x = Foundation.exp((rng.unit() - 0.5) * 40)
            let reference = Foundation.log(x)
            #expect(abs(naturalLog(x) - reference) <= 1e-13 * max(abs(reference), 1), "x=\(x)")
        }
    }

    @Test func naturalExpMatchesFoundation() {
        var rng = SplitMix64(state: 12)
        for _ in 0..<2_000 {
            let y = (rng.unit() - 0.5) * 40
            expectRelativelyClose(naturalExp(y), Foundation.exp(y), relTol: 1e-13, "y=\(y)")
        }
    }

    @Test func positivePowMatchesFoundation() {
        // Covers the ratio and area interpolation ranges used by frame().
        var rng = SplitMix64(state: 13)
        for _ in 0..<2_000 {
            let base = 0.5 + rng.unit() * 3
            let exponent = rng.unit()
            expectRelativelyClose(
                positivePow(base, exponent),
                Foundation.pow(base, exponent),
                relTol: 1e-13,
                "base=\(base) exponent=\(exponent)"
            )
        }
    }

    @Test func powerWithZeroExponentIsExactlyOne() {
        #expect(positivePow(3.7, 0) == 1)
    }
}
