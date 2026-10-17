import Carbon.HIToolbox

/// Physical key position <-> macOS virtual key code (ANSI positions; layout-independent).
enum KeyCodes {
    private static let table: [(code: String, virtual: Int)] = [
        ("KeyA", kVK_ANSI_A), ("KeyB", kVK_ANSI_B), ("KeyC", kVK_ANSI_C), ("KeyD", kVK_ANSI_D),
        ("KeyE", kVK_ANSI_E), ("KeyF", kVK_ANSI_F), ("KeyG", kVK_ANSI_G), ("KeyH", kVK_ANSI_H),
        ("KeyI", kVK_ANSI_I), ("KeyJ", kVK_ANSI_J), ("KeyK", kVK_ANSI_K), ("KeyL", kVK_ANSI_L),
        ("KeyM", kVK_ANSI_M), ("KeyN", kVK_ANSI_N), ("KeyO", kVK_ANSI_O), ("KeyP", kVK_ANSI_P),
        ("KeyQ", kVK_ANSI_Q), ("KeyR", kVK_ANSI_R), ("KeyS", kVK_ANSI_S), ("KeyT", kVK_ANSI_T),
        ("KeyU", kVK_ANSI_U), ("KeyV", kVK_ANSI_V), ("KeyW", kVK_ANSI_W), ("KeyX", kVK_ANSI_X),
        ("KeyY", kVK_ANSI_Y), ("KeyZ", kVK_ANSI_Z),
        ("Digit0", kVK_ANSI_0), ("Digit1", kVK_ANSI_1), ("Digit2", kVK_ANSI_2),
        ("Digit3", kVK_ANSI_3), ("Digit4", kVK_ANSI_4), ("Digit5", kVK_ANSI_5),
        ("Digit6", kVK_ANSI_6), ("Digit7", kVK_ANSI_7), ("Digit8", kVK_ANSI_8),
        ("Digit9", kVK_ANSI_9),
        ("Backquote", kVK_ANSI_Grave), ("Minus", kVK_ANSI_Minus), ("Equal", kVK_ANSI_Equal),
        ("BracketLeft", kVK_ANSI_LeftBracket), ("BracketRight", kVK_ANSI_RightBracket),
        ("Backslash", kVK_ANSI_Backslash), ("Semicolon", kVK_ANSI_Semicolon),
        ("Quote", kVK_ANSI_Quote), ("Comma", kVK_ANSI_Comma), ("Period", kVK_ANSI_Period),
        ("Slash", kVK_ANSI_Slash), ("Space", kVK_Space),
        ("Tab", kVK_Tab), ("Escape", kVK_Escape),
    ]

    private static let virtualByCode: [String: UInt32] = Dictionary(
        uniqueKeysWithValues: table.map { ($0.code, UInt32($0.virtual)) })
    private static let codeByVirtual: [UInt32: String] = Dictionary(
        uniqueKeysWithValues: table.map { (UInt32($0.virtual), $0.code) })

    static func virtualKeyCode(for key: InputKey) -> UInt32? {
        virtualByCode[key.code]
    }

    static func key(forVirtualKeyCode virtual: UInt32) -> InputKey? {
        codeByVirtual[virtual].map { InputKey(code: $0) }
    }
}
