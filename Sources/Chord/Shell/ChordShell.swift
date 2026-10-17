import AppKit

/// What the menu bar reports. Permission outranks pause: a paused app that also lacks
/// Accessibility access still needs the user's attention first.
enum ShellStatus {
    case running
    case paused
    case needsPermission

    var title: String {
        switch self {
        case .running: "Chord: running"
        case .paused: "Chord: paused"
        case .needsPermission: "Chord: needs Accessibility permission"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "keyboard"
        case .paused: "pause.circle"
        case .needsPermission: "exclamationmark.triangle"
        }
    }
}

/// Menu-bar shell: status, pause switch, Accessibility permission flow, launch at login.
/// Holds no window references and makes no window calls; window changes belong to the Executor.
@MainActor
final class ChordShell: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var grantItem = makeItem("Grant Accessibility Access…", #selector(grantAccessibility))
    private lazy var pauseItem = makeItem("Pause Chord", #selector(togglePause))
    private lazy var loginItem = makeItem("Launch at Login", #selector(toggleLaunchAtLogin))
    private var permissionWatch: Timer?
    private var paused = false
    private var accessibilityGranted = false

    private var status: ShellStatus {
        if !accessibilityGranted { return .needsPermission }
        return paused ? .paused : .running
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        accessibilityGranted = AccessibilityPermission.isGranted
        ActionLog.write("launch: accessibility \(accessibilityGranted ? "granted" : "missing")")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        statusItem = item

        statusLine.isEnabled = false
        menu.delegate = self
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(grantItem)
        menu.addItem(pauseItem)
        menu.addItem(loginItem)
        // Placeholder target: the log folder stands in until the diagnostics issue lands.
        menu.addItem(makeItem("Open Log Folder", #selector(openLogFolder)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Chord", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        refresh()

        // Polled for the app's lifetime so a grant (or revoke) lands without a restart.
        // AXIsProcessTrusted is a cheap read.
        permissionWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAccessibility() }
        }

        if !accessibilityGranted {
            explainAccessibility()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        checkAccessibility()
        refresh()
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func refresh() {
        let current = status
        statusLine.title = current.title
        statusItem?.button?.image = NSImage(systemSymbolName: current.symbolName, accessibilityDescription: current.title)
        statusItem?.button?.toolTip = current.title
        grantItem.isHidden = accessibilityGranted
        pauseItem.title = paused ? "Resume Chord" : "Pause Chord"
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    private func checkAccessibility() {
        let granted = AccessibilityPermission.isGranted
        guard granted != accessibilityGranted else { return }
        accessibilityGranted = granted
        ActionLog.write(granted ? "permission: accessibility granted" : "permission: accessibility revoked")
        refresh()
    }

    @objc private func grantAccessibility() {
        explainAccessibility()
    }

    private func explainAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Chord needs Accessibility access"
        alert.informativeText = """
        Chord moves windows only after you allow it under System Settings > \
        Privacy & Security > Accessibility. Until then it won't touch any window. \
        Click Open System Settings, switch Chord on, and this menu will update on its own.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            ActionLog.write("permission: explanation dismissed")
            return
        }
        // The prompt variant registers Chord in the Accessibility list so its switch exists.
        AccessibilityPermission.requestWithPrompt()
        AccessibilityPermission.openSettingsPane()
        ActionLog.write("permission: requested accessibility; opened settings")
    }

    @objc private func togglePause() {
        // Inverse: selecting it again resumes. Nothing is registered yet, so pause has no
        // hotkey to release; later hotkey work must check this flag before consuming keys.
        paused.toggle()
        ActionLog.write(paused ? "pause: paused" : "pause: resumed")
        refresh()
    }

    @objc private func openLogFolder() {
        ActionLog.write("log folder: opened")
        NSWorkspace.shared.open(ActionLog.directory)
    }

    @objc private func toggleLaunchAtLogin() {
        // Inverse: the same item turns it back off.
        let enable = !LaunchAtLogin.isEnabled
        do {
            try LaunchAtLogin.setEnabled(enable)
            ActionLog.write("login item: \(enable ? "enabled" : "disabled")")
            if enable && LaunchAtLogin.needsApproval {
                ActionLog.write("login item: waiting for approval in Login Items")
                LaunchAtLogin.openApprovalSettings()
            }
        } catch {
            ActionLog.write("login item: \(enable ? "enable" : "disable") failed: \(error.localizedDescription)")
            NSAlert(error: error).runModal()
        }
        refresh()
    }
}
