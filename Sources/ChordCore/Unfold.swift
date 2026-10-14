/// A rectangle on the screen, in logical points, before rounding.
///
/// `w * h == area` and `w / h == ratio` hold to floating-point tolerance.
/// `x` and `y` are the origin of the rectangle, centered on the screen.
public struct Frame: Equatable, Sendable {
    public let w: Double
    public let h: Double
    public let x: Double
    public let y: Double
    public let ratio: Double
    public let area: Double

    public init(w: Double, h: Double, x: Double, y: Double, ratio: Double, area: Double) {
        self.w = w
        self.h = h
        self.x = x
        self.y = y
        self.ratio = ratio
        self.area = area
    }
}
/// Constants of the Unfold reference (issue #2).
public enum Unfold {
    /// Golden ratio.
    public static let phi: Double = (1 + Double(5).squareRoot()) / 2

    /// Segment 0 length as a fraction of the animation, `1/phi^2`.
    /// Fixed. The `0.38795` tuning option is rejected: it does not put the
    /// perfect square at `1/phi` (it gives about 0.654).
    public static let knot: Double = 1 / (phi * phi)

    /// S0: 333 x 333*sqrt(2), a 1 : sqrt(2) rectangle (height 470.93).
    public static let smallStop = (w: 333.0, h: 333 * Double(2).squareRoot())

    /// S1: 444 x 630.
    public static let largeStop = (w: 444.0, h: 630.0)
}

/// Smootherstep: 6t^5 - 15t^4 + 10t^3 on [0, 1].
func smootherstep(_ t: Double) -> Double {
    t * t * t * (t * (t * 6 - 15) + 10)
}

/// The Unfold reference `frame()`, ported as a pure function.
///
/// `t` is clamped to [0, 1]. Output is floating point: round only when a
/// frame is applied to a window, never here.
///
/// Stops:
/// - S0 (`t = 0`): `Unfold.smallStop`. Independent of the screen and margin.
/// - S1 (`t = Unfold.knot`): `Unfold.largeStop`.
/// - S2 (`t = 1`): the largest 16:9 box inside `screen - 2 * margin`,
///   centered on the screen.
///
/// Segment 0 (S0 -> S1) interpolates log-area and log-ratio with smootherstep.
/// Segment 1 (S1 -> S2) does the same toward S2. The area is `w * h` and the
/// ratio is `w / h`. Each is interpolated in log space, so `w = sqrt(area *
/// ratio)` and `h = sqrt(area / ratio)`.
///
/// Behavior at the edges of the input domain:
/// - Non-16:9 screens: S2 is a letterboxed 16:9 box, centered.
/// - Small screens, where S1 is larger than S2: the function does not
///   reverse. Segment 1 still moves monotonically from S1 to S2, and the
///   rectangle may exceed the screen during segment 0 when the screen is
///   smaller than S1. The animator (C10) skips the A5 hold in this case.
/// - Portrait screens: unsupported. The output is a well-formed letterboxed
///   16:9 box that stays inside the screen, but Unfold is not offered on
///   portrait displays.
/// - `margin`: the usable area is `screen - 2 * margin` on each axis. It
///   affects only S2. Precondition: the usable area is positive.
///
/// Segment 0 is not an exact pure dilation: `largeStop` is 444 x 630, whose
/// ratio is 0.70476, while S0's ratio is 1/sqrt(2) = 0.70711. Segment 0 is
/// therefore near-constant in ratio (within 0.4%), not constant.
public func frame(
    _ t: Double,
    screenW: Double,
    screenH: Double,
    margin: Double = 0
) -> Frame {
    precondition(!t.isNaN, "frame requires a non-NaN t")
    let sw = screenW - 2 * margin
    let sh = screenH - 2 * margin
    precondition(sw > 0 && sh > 0, "margin leaves no usable screen area")

    var fitW = sw
    var fitH = sw * 9 / 16
    if fitH > sh {
        fitH = sh
        fitW = sh * 16 / 9
    }

    let clamped = min(max(t, 0), 1)
    let s0 = Unfold.smallStop
    let s1 = Unfold.largeStop
    let s2 = (w: fitW, h: fitH)

    let a: (w: Double, h: Double)
    let b: (w: Double, h: Double)
    let u: Double
    if clamped < Unfold.knot {
        a = s0
        b = s1
        u = smootherstep(clamped / Unfold.knot)
    } else {
        a = s1
        b = s2
        u = smootherstep((clamped - Unfold.knot) / (1 - Unfold.knot))
    }

    let ratioA = a.w / a.h
    let ratioB = b.w / b.h
    let areaA = a.w * a.h
    let areaB = b.w * b.h

    let ratio = ratioA * positivePow(ratioB / ratioA, u)
    let area = areaA * positivePow(areaB / areaA, u)

    let w = (area * ratio).squareRoot()
    let h = (area / ratio).squareRoot()
    return Frame(
        w: w,
        h: h,
        x: (screenW - w) / 2,
        y: (screenH - h) / 2,
        ratio: ratio,
        area: area
    )
}
