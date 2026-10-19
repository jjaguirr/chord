import ApplicationServices
import ChordCore
import Foundation

/// A `WorkspaceBackend` over the Accessibility API alone: no AeroSpace, no sockets, no
/// places. It sees the focused window plus every window it has seen before and that
/// still answers, so a snapshot costs a handful of AX reads, not a walk of every app.
///
/// Spike 2 showed AX frames stick; spike 6 showed AeroSpace is too slow to call per
/// frame, so Unfold, Reshape and Carry go through here.
///
/// Coordinates are top-left screen points. A monitor's `bounds` is its visible frame
/// (menu bar and Dock excluded), because that is the area a window may be put in.
/// Every window is reported floating, in `.bench`: AX knows no workspaces.
///
/// Never prompts: without Accessibility trust every call throws `.notConnected`.
public final class AXWindowBackend: WorkspaceBackend, @unchecked Sendable {
    private struct Entry {
        let id: Int
        let element: AXUIElement
    }

    /// Windows remembered beyond the focused one; the oldest are forgotten first.
    private static let maxKnown = 64

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var nextID = 1
    private let writer = AXWindowWriter()
    private let monitors: @Sendable () -> [MonitorSnapshot]
    private let isTrusted: @Sendable () -> Bool

    init(
        monitors: @escaping @Sendable () -> [MonitorSnapshot] = { ScreenGeometry.monitors() },
        isTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.monitors = monitors
        self.isTrusted = isTrusted
        AXReading.configureTimeouts()
    }

    public func snapshot() async throws -> BackendSnapshot {
        guard isTrusted() else { throw BackendError.notConnected }
        return readSnapshot()
    }

    /// The focused window plus every standard, non-minimized window of every visible app
    /// on a monitor. Each is registered, so `focusWindow` can name it afterwards. One AX
    /// walk of all apps per call; only Look uses it.
    public func visibleSnapshot() async throws -> BackendSnapshot {
        guard isTrusted() else { throw BackendError.notConnected }
        return readVisibleSnapshot()
    }

    @discardableResult
    public func moveWindow(_ id: WindowID, to place: Place) async throws -> Place {
        throw BackendError.unknown(reason: "the Accessibility backend has no places")
    }

    @discardableResult
    public func applyFrame(_ id: WindowID, to frame: ScreenRect) async throws -> ScreenRect {
        guard isTrusted() else { throw BackendError.notConnected }
        let window = try element(for: id)
        guard let previous = AXReading.frame(of: window) else {
            forget(id)
            throw BackendError.unknownWindow(id)
        }
        try check(writer.writeFrame(window, to: frame), "set frame", id)
        return previous
    }

    @discardableResult
    public func focusWindow(_ id: WindowID) async throws -> WindowID? {
        guard isTrusted() else { throw BackendError.notConnected }
        let window = try element(for: id)
        let previous = AXReading.focusedWindow().map { WindowID(register([$0])[0]) }
        try check(writer.focus(window), "focus", id)
        return previous
    }

    public func raiseWindow(_ id: WindowID) async throws {
        guard isTrusted() else { throw BackendError.notConnected }
        try check(writer.bringForward(try element(for: id)), "raise", id)
    }

    public func reconnect() async throws {
        guard isTrusted() else { throw BackendError.notConnected }
    }

    // MARK: Registry

    private func readSnapshot() -> BackendSnapshot {
        let focusedID = AXReading.focusedWindow().map { WindowID(register([$0])[0]) }
        let current = remembered()
        var windows: [WindowSnapshot] = []
        var alive: Set<Int> = []
        for entry in current {
            guard let bounds = AXReading.frame(of: entry.element) else { continue }
            alive.insert(entry.id)
            windows.append(
                WindowSnapshot(
                    id: WindowID(entry.id), appName: AXReading.appName(of: entry.element),
                    place: .bench, isFloating: true, bounds: bounds))
        }
        retain(alive)
        return BackendSnapshot(
            monitors: monitors(), windows: windows,
            focusedWindow: focusedID.flatMap { alive.contains($0.rawValue) ? $0 : nil })
    }

    private func readVisibleSnapshot() -> BackendSnapshot {
        let monitors = monitors()
        let focused = AXReading.focusedWindow()
        let listed = AXWindowList.visibleWindows(monitors: monitors)
        let elements = (focused.map { [$0] } ?? []) + listed
        let registered = register(elements)
        let focusedID = focused.map { _ in WindowID(registered[0]) }
        var ids = Set<Int>()
        var windows: [WindowSnapshot] = []
        for (element, id) in zip(elements, registered) {
            guard ids.insert(id).inserted, let bounds = AXReading.frame(of: element) else { continue }
            windows.append(
                WindowSnapshot(
                    id: WindowID(id), appName: AXReading.appName(of: element),
                    place: .bench, isFloating: true, bounds: bounds))
        }
        return BackendSnapshot(
            monitors: monitors, windows: windows,
            focusedWindow: focusedID.flatMap { id in windows.contains { $0.id == id } ? id : nil })
    }

    /// The ids for `windows`, assigning one the first time each is seen. Remembers at most
    /// `maxKnown` windows besides `windows` themselves; the oldest others are forgotten first.
    private func register(_ windows: [AXUIElement]) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        let ids = windows.map { window -> Int in
            if let known = entries.first(where: { CFEqual($0.element, window) }) { return known.id }
            let id = nextID
            nextID += 1
            entries.append(Entry(id: id, element: window))
            return id
        }
        let keep = Set(ids)
        var excess = entries.count - Self.maxKnown
        entries.removeAll { entry in
            guard excess > 0, !keep.contains(entry.id) else { return false }
            excess -= 1
            return true
        }
        return ids
    }

    private func remembered() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    private func retain(_ alive: Set<Int>) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { !alive.contains($0.id) }
    }

    private func forget(_ id: WindowID) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.id == id.rawValue }
    }

    private func element(for id: WindowID) throws -> AXUIElement {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries.first(where: { $0.id == id.rawValue }) else {
            throw BackendError.unknownWindow(id)
        }
        return entry.element
    }

    /// Maps an AX failure onto the backend taxonomy. A window that no longer exists is
    /// `unknownWindow`; anything else may have half applied, so it is `unknown`.
    private func check(_ error: AXError, _ what: String, _ id: WindowID) throws {
        switch error {
        case .success: return
        case .invalidUIElement:
            forget(id)
            throw BackendError.unknownWindow(id)
        case .apiDisabled:
            throw BackendError.notConnected
        default:
            throw BackendError.unknown(reason: "AX \(what) failed on window \(id.rawValue): error \(error.rawValue)")
        }
    }
}
