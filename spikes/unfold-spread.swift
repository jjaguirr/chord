#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

var restoreTargets: [(AXUIElement, CGPoint, CGSize)] = []
func restoreFrames() -> Bool {
    var restored = true
    for (window, point, size) in restoreTargets {
        var p = point, s = size
        guard let pv = AXValueCreate(.cgPoint, &p), let sv = AXValueCreate(.cgSize, &s) else { restored = false; continue }
        let positionSet = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv) == .success
        let sizeSet = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv) == .success
        let actual = frame(window)
        let matches = actual.map {
            abs($0.0.x - point.x) < 2 && abs($0.0.y - point.y) < 2 &&
                abs($0.1.width - size.width) < 2 && abs($0.1.height - size.height) < 2
        } ?? false
        restored = positionSet && sizeSet && matches && restored
    }
    return restored
}
func fail(_ s: String, _ path: String, restore: Bool = true) -> Never {
    let restorationFailed = restore && !restoreFrames()
    fputs("FAIL: \(s)\(restorationFailed ? "; restoration fail path: restore all original window frames" : ""); fail path: \(path)\n", stderr)
    exit(1)
}

func axWindows(_ app: NSRunningApplication) -> [AXUIElement] {
    let root = AXUIElementCreateApplication(app.processIdentifier); var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}
func frame(_ window: AXUIElement) -> (CGPoint, CGSize)? {
    var p: CFTypeRef?, z: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &z) == .success,
          let rawPosition = p, let rawSize = z,
          CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
    let pv = unsafeBitCast(rawPosition, to: AXValue.self), zv = unsafeBitCast(rawSize, to: AXValue.self)
    var point = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(pv, .cgPoint, &point), AXValueGetValue(zv, .cgSize, &size) else { return nil }
    return (point, size)
}
func set(_ window: AXUIElement, _ point: CGPoint, _ size: CGSize) -> Bool {
    var p = point, s = size
    guard let pv = AXValueCreate(.cgPoint, &p), let sv = AXValueCreate(.cgSize, &s) else { return false }
    return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv) == .success && AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv) == .success
}
guard CommandLine.arguments.count == 2 else { fail("usage: unfold-spread.swift <disposable-test-app-bundle-id>", "launch a disposable app with at least 20 visible test windows") }
guard AXIsProcessTrusted() else { fail("Accessibility permission unavailable", "grant Accessibility to terminal in a disposable account; this probe does not change permissions") }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first else { fail("test app not running", "launch the disposable window fixture and rerun") }
let wins = axWindows(app)
guard wins.count >= 20 else { fail("need 20 accessible test windows; found \(wins.count)", "create at least 20 disposable test windows and rerun") }
guard wins.allSatisfy({ frame($0) != nil }) else { fail("could not capture all original frames", "use standard AX windows") }
let originals = wins.compactMap { frame($0) }
for (i, window) in wins.enumerated() { restoreTargets.append((window, originals[i].0, originals[i].1)) }
func run(_ fps: Double, _ selected: [AXUIElement], unfold: Bool) -> ([Double], Int)? {
    let frameBudget = 1000.0 / fps, ticks = 120
    var durations: [Double] = [], frameIndex = 0, skipped = 0
    while frameIndex < ticks {
        let tick = frameIndex, start = DispatchTime.now().uptimeNanoseconds
        for (i, w) in selected.enumerated() {
            let base = originals[i], progress = CGFloat(tick) / CGFloat(ticks - 1)
            let visible = NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: CGSize(width: base.1.width * 2, height: base.1.height * 2))
            let targetSize = unfold
                ? CGSize(width: max(base.1.width, min(max(0, visible.width - 40), visible.width * 0.8)), height: max(base.1.height, min(max(0, visible.height - 40), visible.height * 0.8)))
                : base.1
            let targetPoint = unfold
                ? CGPoint(x: base.0.x + (visible.minX + (visible.width - targetSize.width) / 2 - base.0.x) * progress, y: base.0.y + (visible.minY + (visible.height - targetSize.height) / 2 - base.0.y) * progress)
                : CGPoint(x: base.0.x + CGFloat(tick + 1) * 2 + CGFloat(i * 2), y: base.0.y)
            let interpolatedSize = unfold ? CGSize(width: base.1.width + (targetSize.width - base.1.width) * progress, height: base.1.height + (targetSize.height - base.1.height) * progress) : targetSize
            guard set(w, targetPoint, interpolatedSize) else { return nil }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        durations.append(elapsed)
        let advance = max(1, Int(ceil(elapsed / frameBudget)))
        if advance > 1 { skipped += advance - 1 }
        if elapsed < frameBudget { Thread.sleep(forTimeInterval: (frameBudget - elapsed) / 1000) }
        frameIndex += advance
    }
    return (durations, skipped)
}
guard let at30 = run(30, [wins[0]], unfold: true), let at60 = run(60, [wins[0]], unfold: true), let spread = run(60, wins, unfold: false) else { fail("AX refused a window frame update", "inspect app restrictions and Accessibility authorization") }
for (label, sample, budget) in [("30fps Unfold", at30, 33.33), ("60fps Unfold", at60, 16.67), ("20-window Spread", spread, 16.67)] {
    let sorted = sample.0.sorted(), p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    guard p95 <= budget else { fail("\(label) update p95 \(String(format: "%.2f", p95))ms exceeds \(budget)ms; skipped \(sample.1) frames", "profile AX calls, enable elapsed-time skipping, or select proxy rendering") }
}
guard restoreFrames() else {
    restoreTargets.removeAll()
    fail("failed restoring original window frames", "restore the disposable test windows manually", restore: false)
}
restoreTargets.removeAll()
print("PASS: Unfold 30/60fps and 20-window Spread p95 within 33.33/16.67/16.67ms; elapsed skipping counts \(at30.1)/\(at60.1)/\(spread.1); original frames restored")
