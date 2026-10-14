#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Carbon
import Foundation

let option0 = Int64(kVK_ANSI_0)
let ctrlKeys: Set<Int64> = [Int64(kVK_ANSI_H), Int64(kVK_ANSI_J), Int64(kVK_ANSI_K), Int64(kVK_ANSI_L)]
var carbonCount = 0
var optionCount = 0
var ctrlCount = 0
var registration: EventHotKeyRef?
var finished = false
var carbonMode = false
func fail(_ reason: String, _ path: String) -> Never { fputs("FAIL: \(reason); fail path: \(path)\n", stderr); exit(1) }
if CommandLine.arguments.contains("--preflight") {
    guard CGPreflightListenEventAccess() else { fail("not run: Input Monitoring permission unavailable", "grant Input Monitoring in a disposable account, then rerun the selected mode") }
    fail("not run: Terminal/iTerm/Vim key fixtures absent", "run once with --carbon and once with --tap-fallback in dedicated terminal sessions")
}
guard CommandLine.arguments.count == 2, ["--carbon", "--tap-fallback"].contains(CommandLine.arguments[1]) else { fail("usage: hotkeys.swift --carbon | --tap-fallback", "prepare Terminal, iTerm, and Vim fixtures and run each mode separately") }
guard CGPreflightListenEventAccess() else { fail("Input Monitoring permission unavailable", "grant Input Monitoring in a disposable test account; no setting is changed") }
carbonMode = CommandLine.arguments[1] == "--carbon"
if carbonMode {
    let id = EventHotKeyID(signature: OSType(0x43364348), id: 1)
    let spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in carbonCount += 1; return noErr }, 1, [spec], nil, nil)
    guard installed == noErr, RegisterEventHotKey(UInt32(option0), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &registration) == noErr else { fail("Carbon could not register Option+0", "inspect registration conflicts; rerun --tap-fallback as the fallback") }
}
let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
let tapOptions: CGEventTapOptions = carbonMode ? .listenOnly : .defaultTap
guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: tapOptions, eventsOfInterest: mask, callback: { _, _, event, _ in
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    if code == option0 && event.flags.contains(.maskAlternate) {
        optionCount += 1
        if !carbonMode { return nil } // Consume Option+0 before its alternate character is inserted.
    }
    if ctrlKeys.contains(code) && event.flags.contains(.maskControl) { ctrlCount += 1 }
    return Unmanaged.passUnretained(event)
}, userInfo: nil) else { fail("CGEventTap unavailable", "grant Input Monitoring and rerun; check system tap restrictions") }
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
let label = carbonMode ? "Carbon" : "CGEventTap fallback"
print("\(label): test Option+0 once, then Ctrl+h/j/k/l in Terminal, iTerm, and Vim; verify no alternate character appears in a text field. Press Return here when finished.")
DispatchQueue.global().async { _ = readLine(); finished = true }
while !finished { _ = CFRunLoopRunInMode(.defaultMode, 0.05, true) }
guard optionCount >= 1, ctrlCount >= 12, !carbonMode || carbonCount >= 1 else { fail("\(label) missed required events; Option+0 \(optionCount), Carbon callback \(carbonCount), Ctrl+hjkl \(ctrlCount)", "retry both modes and all four physical Ctrl keys in three terminal environments") }
print("PASS: \(label) captured Option+0 before insertion and Ctrl+hjkl \(ctrlCount) times; threshold Option+0 >=1, Ctrl >=12; verify text-field leakage manually")
