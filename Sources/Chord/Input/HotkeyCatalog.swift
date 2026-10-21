import ChordCore

/// Every global hotkey Chord asks the system for, derived from the `[keys]` bindings.
/// Option is the only base modifier: Ctrl is never bound (Ctrl+hjkl belongs to the
/// user's own remaps), and Cmd combinations belong to apps.
struct HotkeyCatalog: Equatable, Sendable {
    let bindings: [HotkeyBinding]
    private let byIdentity: [HotkeyBinding.Identity: HotkeyBinding]
    private let columnByKey: [InputKey: Int]

    /// Option+0 (tap/hold), Option+R (reshape hold), Option+hjkl and Option+Shift+hjkl,
    /// Option+1-9 and Option+Shift+1-9, Option+bench key and Option+Shift+bench key, Option+Tab. First writer wins
    /// when a config binding collides with another entry.
    init(keys: KeyBindings) {
        var list: [HotkeyBinding] = []
        var seen: Set<HotkeyBinding.Identity> = []
        func add(_ key: InputKey, shift: Bool, _ role: HotkeyRole) {
            let binding = HotkeyBinding(key: key, shift: shift, role: role)
            guard seen.insert(binding.identity).inserted else { return }
            list.append(binding)
        }

        // Option+0 (unfold), Option+R (reshape) and Option+Tab (cycle) are fixed
        // constants, not config bindings.
        add(.digit0, shift: false, .unfold)
        add(.keyR, shift: false, .reshape)
        let directions: [(PhysicalKey, ChordKey)] = [
            (keys.left, .h), (keys.down, .j), (keys.up, .k), (keys.right, .l),
        ]
        for shift in [false, true] {
            for (physical, chordKey) in directions {
                add(InputKey(physical), shift: shift, .direction(chordKey))
            }
        }
        for shift in [false, true] { add(InputKey(keys.bench), shift: shift, .bench) }
        add(.tab, shift: false, .cycle)
        // Places are digit-row keys 1 and up, enumerated generically (0 is unfold). The
        // redacted-tier and vault bindings come from the config and are not special-cased.
        let digits = (1..<10).map { InputKey(code: "Digit\($0)") }
        let placeKeys = digits + [InputKey(keys.redactedTier), InputKey(keys.vault)]
        for shift in [false, true] {
            for key in placeKeys { add(key, shift: shift, .place) }
        }

        // A digit key is its own column. The configured tier and vault keys are the columns
        // of those places; a digit they rebind to keeps its own column.
        var columns: [InputKey: Int] = [:]
        for (index, key) in digits.enumerated() { columns[key] = index + 1 }
        let named: [(PhysicalKey, Int)] = [
            (keys.redactedTier, Workspace.four.rawValue), (keys.vault, GridCell.columnCount),
        ]
        for (physical, column) in named where columns[InputKey(physical)] == nil {
            columns[InputKey(physical)] = column
        }
        columnByKey = columns

        bindings = list
        byIdentity = Dictionary(uniqueKeysWithValues: list.map { ($0.identity, $0) })
    }

    /// The grid column a place key shows (Option+N) or carries to (Option+Shift+N).
    func column(for key: InputKey) -> Int? {
        columnByKey[key]
    }

    func binding(for key: InputKey, shift: Bool) -> HotkeyBinding? {
        byIdentity[HotkeyBinding.Identity(key: key, shift: shift)]
    }
}
