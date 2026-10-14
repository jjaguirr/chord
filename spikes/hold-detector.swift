#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Carbon

let keyCode0 = Int64(kVK_ANSI_0)
var optionDown = false
var holdFired = false
var downAt: UInt64 = 0
var holds = 0
func fail(_ text: String, _ remedy: String) -> Never { fputs("FAIL: \(text); fail path: \(remedy)\n", stderr); exit(1) }

guard CGPreflightListenEventAccess() else { fail("Input Monitoring permission unavailable", "grant Input Monitoring to terminal in a disposable test account; no settings are changed") }
var finished = false
let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, _ in
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let key = keyCode == keyCode0
    let optionKey = keyCode == Int64(kVK_Option) || keyCode == Int64(kVK_RightOption)
    let option = event.flags.contains(.maskAlternate)
    if key && option && type == .keyDown && !optionDown { optionDown = true; holdFired = false; downAt = DispatchTime.now().uptimeNanoseconds }
    if (key && type == .keyUp) || (optionKey && type == .keyUp) { optionDown = false }
    return Unmanaged.passUnretained(event)
}, userInfo: nil) else { fail("could not install global event tap", "grant Input Monitoring to terminal and rerun") }
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.02, 0.02, 0, 0) { _ in
    if optionDown && !holdFired && Double(DispatchTime.now().uptimeNanoseconds - downAt) >= 700_000_000 { holds += 1; holdFired = true }
}
CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
print("Resting-finger baseline: leave keyboard untouched for 10 seconds.")
let baseline = holds
let until = CFAbsoluteTimeGetCurrent() + 10
while CFAbsoluteTimeGetCurrent() < until { _ = CFRunLoopRunInMode(.defaultMode, 0.05, true) }
guard holds == baseline else { fail("hold triggered during resting-finger baseline", "inspect key/modifier mapping and hold threshold") }
print("Press and hold Option+0 for at least 0.7s three times, then press Return.")
DispatchQueue.global().async { _ = readLine(); DispatchQueue.main.async { finished = true } }
while !finished { _ = CFRunLoopRunInMode(.defaultMode, 0.05, true) }
guard holds == 3 else { fail("expected exactly 3 deliberate holds, recorded \(holds)", "repeat three slow holds; inspect threshold and lost key events") }
print("PASS: zero resting activations and 3/3 deliberate holds at 700ms threshold")
