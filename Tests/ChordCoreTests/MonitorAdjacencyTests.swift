import Testing

@testable import ChordCore

private func monitor(_ id: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double, primary: Bool = false)
  -> PickerMonitor
{
  PickerMonitor(id: id, bounds: PickerRect(x: x, y: y, width: w, height: h), isPrimary: primary)
}

private let left = monitor(1, 0, 25, 1440, 875, primary: true)
private let right = monitor(2, 1440, 0, 2560, 1440)
private let below = monitor(3, 200, 900, 1000, 600)

@Test func neighbourIsFoundBeyondTheEdgeAndNotAtACornerOnly() {
  let all = [left, right, below]
  #expect(MonitorAdjacency.neighbour(of: left, in: all, direction: .l) == right)
  #expect(MonitorAdjacency.neighbour(of: right, in: all, direction: .h) == left)
  #expect(MonitorAdjacency.neighbour(of: left, in: all, direction: .j) == below)
  #expect(MonitorAdjacency.neighbour(of: left, in: all, direction: .h) == nil)
  #expect(MonitorAdjacency.neighbour(of: left, in: all, direction: .k) == nil)
  // `below` shares no columns with `right`, so it is not adjacent to it.
  #expect(MonitorAdjacency.neighbour(of: right, in: all, direction: .j) == nil)
}

@Test func nearestOfSeveralNeighboursWins() {
  let far = monitor(4, 4000, 0, 800, 600)
  #expect(MonitorAdjacency.neighbour(of: left, in: [left, far, right], direction: .l) == right)
}

@Test func landingKeepsSizeEntersFlushAndClampsTheOtherAxis() {
  let window = PickerRect(x: 1107, y: 300, width: 333, height: 471)
  let landed = MonitorAdjacency.landing(of: window, from: left.bounds, on: right.bounds, direction: .l)
  #expect(landed == PickerRect(x: 1440, y: 300, width: 333, height: 471))

  let low = PickerRect(x: 1107, y: 800, width: 333, height: 471)
  // Taller position than the small monitor allows: pulled up so it stays on screen.
  let small = monitor(5, 1440, 0, 1000, 900)
  #expect(
    MonitorAdjacency.landing(of: low, from: left.bounds, on: small.bounds, direction: .l)
      == PickerRect(x: 1440, y: 429, width: 333, height: 471))
  // Leftwards it enters through the target's right edge.
  #expect(
    MonitorAdjacency.landing(
      of: PickerRect(x: 1440, y: 300, width: 333, height: 471), from: right.bounds, on: left.bounds, direction: .h)
      == PickerRect(x: 1107, y: 300, width: 333, height: 471))
}

@Test func aWindowLargerThanTheTargetAlignsToItsTopLeft() {
  let window = PickerRect(x: 900, y: 100, width: 1200, height: 800)
  let tiny = monitor(6, 1440, 0, 800, 600)
  #expect(
    MonitorAdjacency.landing(of: window, from: left.bounds, on: tiny.bounds, direction: .l)
      == PickerRect(x: 1440, y: 0, width: 1200, height: 800))
}

@Test func landingSnapsFlushOnlyOnAxesWhereTheTargetIsBeyond() {
  let a = PickerRect(x: 0, y: 0, width: 1920, height: 1080)
  let b = PickerRect(x: 1920, y: 0, width: 1920, height: 1080)
  // Bottom-right corner of A, diagonal press: B is beside A, not below it, so the
  // window keeps its height instead of jumping to B's top.
  let corner = PickerRect(x: 1587, y: 609, width: 333, height: 471)
  #expect(
    MonitorAdjacency.landing(of: corner, from: a, on: b, direction: PickDirection(x: 1, y: 1))
      == PickerRect(x: 1920, y: 609, width: 333, height: 471))
  #expect(
    MonitorAdjacency.landing(of: corner, from: a, on: b, direction: .l)
      == PickerRect(x: 1920, y: 609, width: 333, height: 471))
}
