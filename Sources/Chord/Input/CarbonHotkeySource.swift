import Carbon.HIToolbox

/// Registers every hotkey with `RegisterEventHotKey`. A registered hotkey is consumed by the
/// system, so nothing reaches the focused app. Registration can fail (another app already
/// holds the key); each result is reported with its raw OSStatus. Main thread only.
final class CarbonHotkeySource: HotkeySource {
    let path = CapturePath.carbon
    /// 'CHRD'
    private static let signature: OSType = 0x4348_5244

    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private var bindingsByID: [UInt32: HotkeyBinding] = [:]
    private weak var delegate: HotkeySourceDelegate?

    var isEnabled: Bool { handler != nil }

    func start(bindings: [HotkeyBinding], delegate: HotkeySourceDelegate) -> SourceStartReport {
        stop()
        self.delegate = delegate
        var report = SourceStartReport()

        let specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        var installed: EventHandlerRef?
        let installStatus = specs.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(), carbonHotKeyCallback, buffer.count, buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(), &installed)
        }
        guard installStatus == noErr else {
            report.failure = .handlerInstall(installStatus)
            return report
        }
        handler = installed

        for (index, binding) in bindings.enumerated() {
            guard let keyCode = KeyCodes.virtualKeyCode(for: binding.key) else {
                report.outcomes[binding] = .failed(OSStatus(paramErr))
                continue
            }
            let id = UInt32(index + 1)
            let modifiers = UInt32(optionKey | (binding.shift ? shiftKey : 0))
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                references.append(reference)
                bindingsByID[id] = binding
                report.outcomes[binding] = .registered
            } else {
                report.outcomes[binding] = .failed(status == noErr ? OSStatus(paramErr) : status)
            }
        }
        return report
    }

    func stop() {
        for reference in references { UnregisterEventHotKey(reference) }
        references = []
        bindingsByID = [:]
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        delegate = nil
    }

    fileprivate func dispatch(id: UInt32, kind: UInt32) {
        guard let binding = bindingsByID[id] else { return }
        let phase: KeyPhase = kind == UInt32(kEventHotKeyReleased) ? .up : .down
        let event = RawKeyEvent(
            key: binding.key, modifiers: HeldModifiers(option: true, shift: binding.shift), phase: phase)
        _ = delegate?.hotkeySource(.carbon, didReceive: event)
    }
}

private let carbonHotKeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    Unmanaged<CarbonHotkeySource>.fromOpaque(userData).takeUnretainedValue()
        .dispatch(id: hotKeyID.id, kind: GetEventKind(event))
    return noErr
}
