import Testing
@testable import ChordCore

@Suite("frame()")
struct FrameTests {
    /// The five resolutions named in issue #2.
    static let resolutions: [(w: Double, h: Double)] = [
        (1280, 720), (1366, 768), (1440, 900), (2560, 1440), (3840, 2160),
    ]

    private func sampleT(_ count: Int) -> [Double] {
        (0...count).map { Double($0) / Double(count) }
    }

    // MARK: Stops and clamping (acceptance 1)

    @Test func frameZeroIsSmallStop() {
        let f = frame(0, screenW: 1280, screenH: 720)
        expectRelativelyClose(f.w, 333, relTol: 1e-12)
        expectRelativelyClose(f.h, 333 * 2.0.squareRoot(), relTol: 1e-12)
    }

    @Test func frameOneIsLargestSixteenNineBoxAtEachResolution() {
        for (w, h) in Self.resolutions {
            let f = frame(1, screenW: w, screenH: h)
            let expectedH = min(w * 9 / 16, h)
            let expectedW = expectedH * 16 / 9
            expectRelativelyClose(f.h, expectedH, relTol: 1e-12, "\(w)x\(h) h")
            expectRelativelyClose(f.w, expectedW, relTol: 1e-12, "\(w)x\(h) w")
        }
    }

    @Test func frameOneOnSixteenNineDisplaysIsFullFit() {
        let hd = frame(1, screenW: 1280, screenH: 720)
        expectRelativelyClose(hd.w, 1280, relTol: 1e-12)
        expectRelativelyClose(hd.h, 720, relTol: 1e-12)
        let qhd = frame(1, screenW: 2560, screenH: 1440)
        expectRelativelyClose(qhd.w, 2560, relTol: 1e-12)
        expectRelativelyClose(qhd.h, 1440, relTol: 1e-12)
    }

    @Test func tIsClampedToUnitInterval() {
        let below = frame(-5, screenW: 1440, screenH: 900)
        let zero = frame(0, screenW: 1440, screenH: 900)
        let above = frame(7, screenW: 1440, screenH: 900)
        let one = frame(1, screenW: 1440, screenH: 900)
        #expect(below.w == zero.w)
        #expect(below.h == zero.h)
        #expect(above.w == one.w)
        #expect(above.h == one.h)
    }

    // MARK: Segment structure (acceptance 2)

    @Test func ratioAndAreaAreContinuousAcrossKnot() {
        for (w, h) in Self.resolutions {
            let before = frame(Unfold.knot - 1e-9, screenW: w, screenH: h)
            let after = frame(Unfold.knot + 1e-9, screenW: w, screenH: h)
            #expect(abs(before.ratio - after.ratio) < 1e-6, "\(w)x\(h)")
            #expect(abs(before.area - after.area) / after.area < 1e-6, "\(w)x\(h)")
        }
    }

    @Test func areaIsMonotonicOverWholeAnimation() {
        for (w, h) in Self.resolutions {
            var previous = -Double.infinity
            for t in sampleT(10_000) {
                let area = frame(t, screenW: w, screenH: h).area
                #expect(area >= previous * (1 - 1e-12), "\(w)x\(h) t=\(t)")
                previous = area
            }
        }
    }

    @Test func ratioIsMonotonicWithinEachSegment() {
        // Segment 0 falls from 1/sqrt(2) to the 444x630 ratio. Segment 1 rises to 16:9.
        for (w, h) in Self.resolutions {
            let segment0 = (0...10_000).map { Double($0) / 10_000 * Unfold.knot }
            let segment1 = (0...10_000).map { Unfold.knot + Double($0) / 10_000 * (1 - Unfold.knot) }
            var previous = frame(0, screenW: w, screenH: h).ratio
            for t in segment0 {
                let ratio = frame(t, screenW: w, screenH: h).ratio
                #expect(ratio <= previous * (1 + 1e-12), "\(w)x\(h) seg0 t=\(t)")
                previous = ratio
            }
            previous = frame(Unfold.knot, screenW: w, screenH: h).ratio
            for t in segment1 {
                let ratio = frame(t, screenW: w, screenH: h).ratio
                #expect(ratio >= previous * (1 - 1e-12), "\(w)x\(h) seg1 t=\(t)")
                previous = ratio
            }
        }
    }

    @Test func segmentZeroRatioIsNearConstant() {
        // The stops are 333x470.93 and 444x630, so segment 0 is not an exact
        // dilation. Its ratio stays within 0.4% of 1/sqrt(2). See frame()'s doc.
        let ratios = sampleT(10_000).filter { $0 <= Unfold.knot }.map {
            frame($0, screenW: 1280, screenH: 720).ratio
        }
        let spread = (ratios.max()! - ratios.min()!) / ratios.min()!
        #expect(spread < 0.004)
        expectRelativelyClose(ratios[0], 1 / 2.0.squareRoot(), relTol: 1e-12)
    }

    // MARK: Identities (acceptance 3)

    @Test func widthHeightMatchAreaAndRatioOnRandomSamples() {
        var rng = SplitMix64(state: 2)
        for _ in 0..<1_000 {
            let t = rng.unit()
            let f = frame(t, screenW: 1440, screenH: 900)
            expectRelativelyClose(f.w * f.h, f.area, relTol: 1e-12, "t=\(t)")
            expectRelativelyClose(f.w / f.h, f.ratio, relTol: 1e-12, "t=\(t)")
        }
    }

    // MARK: Centering and containment (acceptance 4)

    @Test func rectangleIsCenteredAndInsideScreenAtEveryTestResolution() {
        for (screenW, screenH) in Self.resolutions {
            for t in sampleT(1_000) {
                let f = frame(t, screenW: screenW, screenH: screenH)
                let context = "\(screenW)x\(screenH) t=\(t)"
                expectRelativelyClose(f.x + f.w / 2, screenW / 2, relTol: 1e-12, context)
                expectRelativelyClose(f.y + f.h / 2, screenH / 2, relTol: 1e-12, context)
                #expect(f.x >= -1e-9, Comment(rawValue: context))
                #expect(f.y >= -1e-9, Comment(rawValue: context))
                #expect(f.x + f.w <= screenW + 1e-9, Comment(rawValue: context))
                #expect(f.y + f.h <= screenH + 1e-9, Comment(rawValue: context))
            }
        }
    }

    // MARK: Edge-case behavior (acceptance 6)

    @Test func nonSixteenNineScreenIsLetterboxed() {
        // 1000x1000: a 16:9 box fits by width. 1440x900 (16:10): by width too.
        let square = frame(1, screenW: 1000, screenH: 1000)
        expectRelativelyClose(square.w, 1000, relTol: 1e-12)
        expectRelativelyClose(square.h, 562.5, relTol: 1e-12)
        expectRelativelyClose(square.y, 218.75, relTol: 1e-12)

        let sixteenTen = frame(1, screenW: 1440, screenH: 900)
        expectRelativelyClose(sixteenTen.w, 1440, relTol: 1e-12)
        expectRelativelyClose(sixteenTen.h, 810, relTol: 1e-12)
        expectRelativelyClose(sixteenTen.y, 45, relTol: 1e-12)
    }

    @Test func smallScreenDoesNotReverse() {
        // 600x400 is smaller than S1 (444x630) in height. S2 is 600x337.5.
        // Area falls from S1 to S2 and must not change direction within segment 1.
        let samples = (0...10_000).map { Unfold.knot + Double($0) / 10_000 * (1 - Unfold.knot) }
        let areas = samples.map { frame($0, screenW: 600, screenH: 400).area }
        let differences = zip(areas, areas.dropFirst()).map { $1 - $0 }
        let signs = Set(differences.filter { abs($0) > 1e-6 }.map { $0 > 0 })
        #expect(signs.count == 1, "area reversed within segment 1")

        let s1 = frame(Unfold.knot, screenW: 600, screenH: 400)
        expectRelativelyClose(s1.w, 444, relTol: 1e-12)
        expectRelativelyClose(s1.h, 630, relTol: 1e-12)
        let s2 = frame(1, screenW: 600, screenH: 400)
        expectRelativelyClose(s2.w, 600, relTol: 1e-12)
        expectRelativelyClose(s2.h, 337.5, relTol: 1e-12)
    }

    @Test func portraitStaysInsideButIsUnsupported() {
        // Portrait is documented unsupported. The output must still be well-formed.
        let f = frame(1, screenW: 800, screenH: 1200)
        expectRelativelyClose(f.w, 800, relTol: 1e-12)
        expectRelativelyClose(f.h, 450, relTol: 1e-12)
        expectRelativelyClose(f.y, 375, relTol: 1e-12)
    }

    // MARK: Margin

    @Test func marginDoesNotAffectSmallStop() {
        let zero = frame(0, screenW: 1280, screenH: 720)
        let margined = frame(0, screenW: 1280, screenH: 720, margin: 20)
        expectRelativelyClose(margined.w, zero.w, relTol: 1e-12)
        expectRelativelyClose(margined.h, zero.h, relTol: 1e-12)
    }

    @Test func marginDoesNotAffectLargeStop() {
        // Segment 0 ends on S1, so S1 is also independent of margin.
        let zero = frame(Unfold.knot, screenW: 1280, screenH: 720)
        let margined = frame(Unfold.knot, screenW: 1280, screenH: 720, margin: 20)
        expectRelativelyClose(margined.w, zero.w, relTol: 1e-12)
        expectRelativelyClose(margined.h, zero.h, relTol: 1e-12)
    }

    @Test func marginShrinksLargestSixteenNineBoxAndCenters() {
        // 1280x720 with margin 20 leaves 1240x680. 16:9 fits by height: 680 x 1208.89.
        let f = frame(1, screenW: 1280, screenH: 720, margin: 20)
        expectRelativelyClose(f.h, 680, relTol: 1e-12)
        expectRelativelyClose(f.w, 680 * 16 / 9, relTol: 1e-12)
        expectRelativelyClose(f.x, (1280 - 680 * 16 / 9) / 2, relTol: 1e-12)
        expectRelativelyClose(f.y, 20, relTol: 1e-12)
    }
}
