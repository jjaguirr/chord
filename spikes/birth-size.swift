#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

func fail(_ message: String, _ remedy: String) -> Never { fputs("FAIL: \(message); fail path: \(remedy)\n", stderr); exit(1) }
if CommandLine.arguments.contains("--preflight") {
    guard AXIsProcessTrusted() else { fail("not run: Accessibility permission unavailable", "grant Accessibility to terminal in a disposable account, then rerun without --preflight") }
    fail("not run: no fresh test-window fixture or app minimum supplied", "launch a dedicated test app, create a fresh window, and rerun with its bundle ID")
}
func size(_ e: AXUIElement) -> CGSize? { var raw: CFTypeRef?; guard AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &raw) == .success, let value = raw, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }; let axValue = unsafeBitCast(value, to: AXValue.self); var result = CGSize.zero; guard AXValueGetValue(axValue, .cgSize, &result) else { return nil }; return result }
guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 4 else { fail("usage: birth-size.swift <disposable-test-app-bundle-id> [app-min-width app-min-height]", "create a fresh test window; pass the documented app minimum dimensions if it exceeds the target") }
guard AXIsProcessTrusted() else { fail("Accessibility permission unavailable", "grant Accessibility to terminal in a disposable account; this probe does not change permissions") }
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first else { fail("test app is not running", "launch the disposable test app and rerun") }
let expectedMinimum: CGSize? = {
    guard CommandLine.arguments.count == 4, let w = Double(CommandLine.arguments[2]), let h = Double(CommandLine.arguments[3]), w > 0, h > 0 else { return nil }
    return CGSize(width: max(333, w), height: max(471, h))
}()
if CommandLine.arguments.count == 4 && expectedMinimum == nil { fail("invalid app minimum dimensions", "provide positive documented minimum width and height") }
let root = AXUIElementCreateApplication(app.processIdentifier)
var rawWindows: CFTypeRef?
guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &rawWindows) == .success, let windows = rawWindows as? [AXUIElement], windows.count == 1, let window = windows.first else { fail("expected exactly one fresh accessible window", "close other app windows and create one fresh test window immediately before running") }
guard let original = size(window) else { fail("cannot read fresh-window size", "use an app exposing AX size") }
func restore() { var s = original; if let v = AXValueCreate(.cgSize, &s) { _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) } }
var requested = CGSize(width: 333, height: 471)
guard let request = AXValueCreate(.cgSize, &requested) else { fail("could not encode requested size", "inspect AXValue support") }
if AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, request) != .success { restore(); fail("AX refused 333x471", "record app behavior and inspect its documented minimum size") }
Thread.sleep(forTimeInterval: 0.5)
guard let actual = size(window) else { restore(); fail("cannot read resulting size", "inspect app AX attributes") }
let exact = abs(actual.width - 333) < 2 && abs(actual.height - 471) < 2
let knownClamp = expectedMinimum.map { abs(actual.width - $0.width) < 2 && abs(actual.height - $0.height) < 2 } ?? false
restore()
guard exact || knownClamp else { fail("requested 333x471 yielded \(actual.width)x\(actual.height); no matching app minimum supplied", "record the app's documented minimum dimensions and rerun with them") }
print("PASS: fresh test window accepted \(exact ? "333x471" : "documented minimum clamp \(actual.width)x\(actual.height)"); threshold exact 333x471 or explicitly supplied app minimum; original size restored")
