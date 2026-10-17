import ApplicationServices
import CoreGraphics

/// Session event tap for keys Carbon cannot take, and a cross-check on the keys it did.
/// It consumes only what the delegate tells it to. The caller must have confirmed
/// Accessibility and Input Monitoring first: creating a tap without them can raise a
/// system prompt, which this app never triggers. Main thread only.
final class EventTapSource: HotkeySource {
    let path = CapturePath.tap

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private weak var delegate: HotkeySourceDelegate?
    private var keyCodes: Set<UInt32> = []
    /// Key codes whose press was forwarded, so repeats and releases follow without modifiers.
    private var forwardedDown: Set<UInt32> = []

    var isEnabled: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    func start(bindings: [HotkeyBinding], delegate: HotkeySourceDelegate) -> SourceStartReport {
        stop()
        self.delegate = delegate
        var codes = Set(bindings.compactMap { KeyCodes.virtualKeyCode(for: $0.key) })
        if let escape = KeyCodes.virtualKeyCode(for: .escape) { codes.insert(escape) }
        keyCodes = codes

        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard
            let created = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            return SourceStartReport(failure: .tapCreateFailed)
        }
        port = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return SourceStartReport()
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        port = nil
        runLoopSource = nil
        forwardedDown = []
        keyCodes = []
        delegate = nil
    }

    /// Returns true when the event must be swallowed.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            let cause = type == .tapDisabledByTimeout ? "timeout: callback ran too long" : "user input"
            delegate?.hotkeySource(.tap, wasDisabledBy: cause)
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .keyDown, .keyUp:
            break
        default:
            return false
        }

        let code = UInt32(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCodes.contains(code), let key = KeyCodes.key(forVirtualKeyCode: code) else { return false }
        let flags = event.flags
        let modifiers = HeldModifiers(
            option: flags.contains(.maskAlternate), shift: flags.contains(.maskShift),
            control: flags.contains(.maskControl), command: flags.contains(.maskCommand))

        let phase: KeyPhase
        if type == .keyUp {
            guard forwardedDown.remove(code) != nil else { return false }
            phase = .up
        } else if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            guard forwardedDown.contains(code) else { return false }
            phase = .autorepeat
        } else {
            // Other keys are not forwarded, so ordinary typing never reaches Chord.
            guard modifiers.option || key == .escape else { return false }
            forwardedDown.insert(code)
            phase = .down
        }
        let decision = delegate?.hotkeySource(
            .tap, didReceive: RawKeyEvent(key: key, modifiers: modifiers, phase: phase))
        return decision == .consume
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let source = Unmanaged<EventTapSource>.fromOpaque(userInfo).takeUnretainedValue()
    return source.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
