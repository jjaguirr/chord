#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Carbon
import Foundation

let option0 = Int64(kVK_ANSI_0)
struct CtrlTrial {
    let context: String
    let key: String
    let code: Int64
    let bundleIDs: Set<String>
}
let terminalBundle = "com.apple.Terminal"
let iTermBundle = "com.googlecode.iterm2"
let ctrlTrials = [
    CtrlTrial(context: "Terminal", key: "h", code: Int64(kVK_ANSI_H), bundleIDs: [terminalBundle]),
    CtrlTrial(context: "Terminal", key: "j", code: Int64(kVK_ANSI_J), bundleIDs: [terminalBundle]),
    CtrlTrial(context: "Terminal", key: "k", code: Int64(kVK_ANSI_K), bundleIDs: [terminalBundle]),
    CtrlTrial(context: "Terminal", key: "l", code: Int64(kVK_ANSI_L), bundleIDs: [terminalBundle]),
    CtrlTrial(context: "iTerm", key: "h", code: Int64(kVK_ANSI_H), bundleIDs: [iTermBundle]),
    CtrlTrial(context: "iTerm", key: "j", code: Int64(kVK_ANSI_J), bundleIDs: [iTermBundle]),
    CtrlTrial(context: "iTerm", key: "k", code: Int64(kVK_ANSI_K), bundleIDs: [iTermBundle]),
    CtrlTrial(context: "iTerm", key: "l", code: Int64(kVK_ANSI_L), bundleIDs: [iTermBundle]),

]
var currentCtrlTrial: CtrlTrial?
var ctrlTrialHit = false
var carbonCount = 0
var optionCount = 0
var registration: EventHotKeyRef?
var finished = false
var carbonMode = false
func fail(_ reason: String, _ path: String) -> Never { fputs("FAIL: \(reason); fail path: \(path)\n", stderr); exit(1) }

guard CommandLine.arguments.count == 2, ["--carbon", "--tap-fallback"].contains(CommandLine.arguments[1]) else { fail("usage: hotkeys.swift --carbon | --tap-fallback", "prepare Terminal and iTerm fixtures; test Vim-in-terminal behavior manually") }
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
        if !carbonMode { return nil }
    }
    if let trial = currentCtrlTrial,
       code == trial.code,
       event.flags.contains(.maskControl),
       trial.bundleIDs.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") {
        ctrlTrialHit = true
    }
    return Unmanaged.passUnretained(event)
}, userInfo: nil) else { fail("CGEventTap unavailable", "grant Input Monitoring and rerun; check system tap restrictions") }
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
let application = NSApplication.shared
application.setActivationPolicy(.regular)
let leakageWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
    styleMask: [.titled, .closable],
    backing: .buffered,
    defer: false
)
leakageWindow.title = "\(carbonMode ? "Carbon" : "CGEventTap fallback") Option+0 leakage check"
let leakageField = NSTextField(frame: NSRect(x: 20, y: 30, width: 320, height: 24))
leakageWindow.contentView?.addSubview(leakageField)
leakageWindow.center()
leakageWindow.makeKeyAndOrderFront(nil)
application.activate(ignoringOtherApps: true)
CFRunLoopRunInMode(.defaultMode, 0.1, false)
leakageField.stringValue = ""
guard leakageWindow.makeFirstResponder(leakageField) else {
    fail("\(carbonMode ? "Carbon" : "CGEventTap fallback") could not focus the leakage-check field", "rerun in an interactive desktop session and ensure the disposable field opens")
}
let label = carbonMode ? "Carbon" : "CGEventTap fallback"
print("\(label): click the disposable text field, press Option+0 once, then press Return in this terminal. Next complete each prompted Ctrl trial. Vim-in-Terminal/iTerm trials are manual and cannot be verified by this probe.")
DispatchQueue.global().async { _ = readLine(); DispatchQueue.main.async { finished = true } }
while !finished { _ = CFRunLoopRunInMode(.defaultMode, 0.05, true) }
guard leakageField.stringValue.isEmpty else {
    fail("\(label) leaked alternate text into the disposable field: \(leakageField.stringValue.debugDescription)", "inspect hotkey interception; rerun this mode and require an empty text field")
}
guard optionCount >= 1, !carbonMode || carbonCount >= 1 else { fail("\(label) missed Option+0; Option+0 \(optionCount), Carbon callback \(carbonCount)", "retry both modes and verify Option+0 is captured before insertion") }
for trial in ctrlTrials {
    currentCtrlTrial = trial
    ctrlTrialHit = false
    print("Test Ctrl+\(trial.key) in \(trial.context), then press Return here.")
    finished = false
    DispatchQueue.global().async { _ = readLine(); DispatchQueue.main.async { finished = true } }
    while !finished { _ = CFRunLoopRunInMode(.defaultMode, 0.05, true) }
    guard ctrlTrialHit else { fail("\(label) missed Ctrl+\(trial.key) in \(trial.context)", "retry this physical key in the named environment; complete every prompted trial") }
}
leakageWindow.close()
print("PASS: \(label) captured Option+0 without text leakage and every physical Ctrl+h/j/k/l trial in Terminal and iTerm; Vim-in-Terminal/iTerm remain manual and unverified")
