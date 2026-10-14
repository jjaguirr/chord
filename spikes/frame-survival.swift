#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

func fail(_ reason: String, _ path: String) -> Never { fputs("FAIL: \(reason); fail path: \(path)\n", stderr); exit(1) }
func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? { var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let raw = value, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }; return unsafeBitCast(raw, to: AXValue.self) }

guard CommandLine.arguments.count == 2 else { fail("usage: frame-survival.swift <disposable-test-app-bundle-id>", "launch a disposable app with a visible test window and pass its bundle ID") }
guard AXIsProcessTrusted() else { fail("Accessibility permission unavailable", "grant Accessibility to the terminal in a disposable test account; this probe does not change permissions") }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first else { fail("test app is not running", "launch the disposable test app and rerun") }
let root = AXUIElementCreateApplication(app.processIdentifier)
var rawWindows: CFTypeRef?
guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &rawWindows) == .success, let raw = rawWindows as? [AXUIElement], raw.count == 1, let window = raw.first else { fail("expected exactly one accessible test window", "close other app windows and launch one standard AX test window") }
guard let rawPos = axValue(window, kAXPositionAttribute), let rawSize = axValue(window, kAXSizeAttribute) else { fail("cannot read AX frame", "use a test app exposing AX position and size") }
var x = CGPoint.zero, s = CGSize.zero
guard AXValueGetValue(rawPos, .cgPoint, &x), AXValueGetValue(rawSize, .cgSize, &s) else { fail("AX frame has unexpected type", "inspect test app AX attributes") }
let originalX = x, originalS = s
func restore() { var restorePos = originalX, restoreSize = originalS; if let p = AXValueCreate(.cgPoint, &restorePos), let z = AXValueCreate(.cgSize, &restoreSize) { _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p); _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, z) } }
let targetX = CGPoint(x: x.x + 37, y: x.y + 29)
let targetSize = CGSize(width: s.width + 20, height: s.height + 20)
var newPos = targetX, newSize = targetSize
guard let posValue = AXValueCreate(.cgPoint, &newPos), let sizeValue = AXValueCreate(.cgSize, &newSize) else { fail("could not encode AX frame", "inspect AX coordinate support") }
let positionSet = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue) == .success
let sizeSet = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
guard positionSet && sizeSet else { restore(); fail("AX refused requested test frame", "record app refusal and select another substrate/window API") }
Thread.sleep(forTimeInterval: 5)
let survived: Bool = {
    guard let afterPos = axValue(window, kAXPositionAttribute), AXValueGetValue(afterPos, .cgPoint, &x), abs(x.x - targetX.x) < 2,
          let afterSize = axValue(window, kAXSizeAttribute), AXValueGetValue(afterSize, .cgSize, &s) else { return false }
    return abs(s.width - targetSize.width) < 2 && abs(s.height - targetSize.height) < 2
}()
restore()
guard survived else { fail("requested frame did not survive 5 seconds", "record app behavior and select another substrate/window API") }
print("PASS: AX frame position and size survived 5s within 2pt; threshold 5s; original frame restored")
