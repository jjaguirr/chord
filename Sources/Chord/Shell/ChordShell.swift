import AppKit
import ChordCore

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

/// Menu-bar shell: status, pause switch, Accessibility permission flow, launch at login, and update check.
/// Holds no window references and makes no window calls; window changes belong to the Executor.
@MainActor
final class ChordShell: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var grantItem = makeItem("Grant Accessibility Access…", #selector(grantAccessibility))
    private lazy var pauseItem = makeItem("Pause Chord", #selector(togglePause))
    private lazy var loginItem = makeItem("Launch at Login", #selector(toggleLaunchAtLogin))
    private lazy var checkUpdatesItem = makeItem("Check for Updates…", #selector(checkForUpdates))
    private lazy var availableUpdateItem = makeItem("", #selector(showAvailableUpdate))
    private var permissionWatch: Timer?
    private var paused = false
    private var accessibilityGranted = false
    private var config = Config.defaults
    private var availableRelease: LatestRelease?
    private var updateCheckRunning = false
    private var updateTimer: Timer?
    private static let lastCheckKey = "updates.lastCheckedAt"
    private var installedVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
    private let crashMenu = NSMenu()
    private let crashItem = NSMenuItem(title: "Recent Crash Reports", action: nil, keyEquivalent: "")
    private var inputCapture: InputCapture?
    private var inputTimer: Timer?
    private var windowMotion: WindowMotion?
    private var inputMonitoringGranted = false
    private let inputMenu = NSMenu()
    private let inputProblemItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let inputStatusItem = NSMenuItem(title: "Input status", action: nil, keyEquivalent: "")

    private var status: ShellStatus {
        if !accessibilityGranted { return .needsPermission }
        return paused ? .paused : .running
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        accessibilityGranted = AccessibilityPermission.isGranted
        ActionLog.live.write("launch: accessibility \(accessibilityGranted ? "granted" : "missing")")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        statusItem = item

        statusLine.isEnabled = false
        menu.delegate = self
        menu.addItem(statusLine)
        inputProblemItem.isEnabled = false
        inputProblemItem.isHidden = true
        menu.addItem(inputProblemItem)
        menu.addItem(.separator())
        menu.addItem(grantItem)
        menu.addItem(pauseItem)
        menu.addItem(loginItem)
        menu.addItem(availableUpdateItem)
        menu.addItem(checkUpdatesItem)
        inputStatusItem.submenu = inputMenu
        menu.addItem(inputStatusItem)
        menu.addItem(makeItem("Open Log Folder", #selector(openLogFolder)))
        menu.addItem(makeItem("Copy Diagnostics", #selector(copyDiagnostics)))
        crashItem.submenu = crashMenu
        menu.addItem(crashItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Chord", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        config = ConfigFile.load()
        startInputCapture()

        refresh()

        // Polled for the app's lifetime so a grant (or revoke) lands without a restart.
        // AXIsProcessTrusted is a cheap read.
        permissionWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkAccessibility()
                self?.checkInputMonitoring()
            }
        }

        if config.updates.backgroundCheck {
            startBackgroundUpdateChecks()
        }

        if !accessibilityGranted {
            explainAccessibility()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        checkAccessibility()
        checkInputMonitoring()
        refresh()
        refreshCrashReports()
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
        checkUpdatesItem.isEnabled = !updateCheckRunning
        availableUpdateItem.isHidden = availableRelease == nil
        if let release = availableRelease {
            availableUpdateItem.title = "Update available: \(release.tag)"
        }
        refreshInputStatus()
    }

    @objc private func checkForUpdates() {
        runUpdateCheck(manual: true)
    }

    @objc private func showAvailableUpdate() {
        guard let release = availableRelease else { return }
        presentUpdate(release)
    }

    private func startBackgroundUpdateChecks() {
        checkBackgroundUpdateIfDue()
        // Hourly ticks; the 24-hour gap comes from the stored last-check time, so a relaunch does not re-check early.
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkBackgroundUpdateIfDue() }
        }
    }

    private func checkBackgroundUpdateIfDue() {
        let last = (UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date)?.timeIntervalSince1970
        if !UpdateSchedule.isBackgroundCheckDue(lastAttemptAt: last, now: Date().timeIntervalSince1970) { return }
        runUpdateCheck(manual: false)
    }

    private func runUpdateCheck(manual: Bool) {
        guard !updateCheckRunning else { return }
        updateCheckRunning = true
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        refresh()
        ActionLog.live.write("update check: started (\(manual ? "manual" : "background"))")
        let version = installedVersion
        Task {
            let result = await UpdateChecker.run(currentVersion: version)
            updateCheckRunning = false
            handleUpdateResult(result, manual: manual)
        }
    }

    private func handleUpdateResult(_ result: UpdateCheckResult, manual: Bool) {
        let current = installedVersion ?? "an unversioned build"
        switch result {
        case .upToDate:
            availableRelease = nil
            ActionLog.live.write("update check: up to date at \(current)")
            if manual { showMessage("Chord is up to date", "You have \(current).") }
        case .available(let release):
            availableRelease = release
            ActionLog.live.write("update check: \(release.tag) available; running \(current)")
            if manual { presentUpdate(release) }
        case .failed(let reason):
            ActionLog.live.write("update check: failed: \(reason)")
            if manual { showMessage("Couldn't check for updates", reason) }
        }
        refresh()
    }


    private func presentUpdate(_ release: LatestRelease) {
        let alert = NSAlert()
        alert.messageText = "Chord \(release.tag) is available"
        alert.informativeText = """
        You have \(installedVersion ?? "an unversioned build"). Release notes and download: \
        \(release.pageURL.absoluteString)
        Chord never downloads or installs updates itself.
        """
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            ActionLog.live.write("update check: download page not opened")
            return
        }
        ActionLog.live.write("update check: opened download page for \(release.tag)")
        NSWorkspace.shared.open(release.pageURL)
    }

    private func showMessage(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private func checkAccessibility() {
        let granted = AccessibilityPermission.isGranted
        guard granted != accessibilityGranted else { return }
        accessibilityGranted = granted
        ActionLog.live.write(granted ? "permission: accessibility granted" : "permission: accessibility revoked")
        restartInputCapture(reason: "accessibility \(granted ? "granted" : "revoked")")
        refresh()
    }

    private func checkInputMonitoring() {
        let granted = SystemInputPermissions().inputMonitoringGranted
        guard granted != inputMonitoringGranted else { return }
        inputMonitoringGranted = granted
        ActionLog.live.write(granted ? "permission: input monitoring granted" : "permission: input monitoring revoked")
        restartInputCapture(reason: "input monitoring \(granted ? "granted" : "revoked")")
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
            ActionLog.live.write("permission: explanation dismissed")
            return
        }
        // The prompt variant registers Chord in the Accessibility list so its switch exists.
        AccessibilityPermission.requestWithPrompt()
        AccessibilityPermission.openSettingsPane()
        ActionLog.live.write("permission: requested accessibility; opened settings")
    }

    @objc private func togglePause() {
        // Inverse: selecting it again resumes. Pausing releases every hotkey so no key is
        // consumed while paused; resuming re-runs the input self-check.
        paused.toggle()
        ActionLog.live.write(paused ? "pause: paused" : "pause: resumed")
        if paused {
            inputCapture?.stop()
            Task { await windowMotion?.cancel() }
        } else {
            inputCapture?.start()
        }
        refresh()
    }

    @objc private func openLogFolder() {
        ActionLog.live.write("log folder: opened")
        NSWorkspace.shared.open(ActionLog.live.directory)
    }

    @objc private func copyDiagnostics() {
        // Read-only: writes only the clipboard, which Chord does not own, so there is no
        // inverse to record. The copy itself is logged.
        var text = DiagnosticsCollector.render(config: config)
        if let capture = inputCapture { text += "\n\n" + capture.status().render() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ActionLog.live.write("diagnostics: copied to clipboard")
    }

    // MARK: Input capture

    private func startInputCapture() {
        let clock = SystemInputClock()
        let focused = FocusedGeometry(clock: clock)
        let logLine: @Sendable (String) -> Void = { ActionLog.live.write($0) }
        // The Accessibility backend and the Executor are the only path from a key to a
        // window. The backend never prompts: without trust every call fails and is logged.
        let executor = Executor(backend: AXWindowBackend(), logSink: logLine)
        let motion = WindowMotion(
            executor: executor, clock: clock,
            stepWindow: Double(config.timing.unfoldStepWindowMs) / 1000, log: logLine)
        motion.start()
        windowMotion = motion

        let capture = InputCapture(
            config: config, carbon: CarbonHotkeySource(), tap: EventTapSource(),
            permissions: SystemInputPermissions(), clock: clock,
            geometry: { MainActor.assumeIsolated { focused.current() } },
            logSink: logLine)
        capture.tickRequest = { [weak self] needed in
            MainActor.assumeIsolated { self?.setInputTicking(needed) }
        }
        capture.intentHandler = { intents in
            MainActor.assumeIsolated { motion.submit(.intents(intents)) }
        }
        inputCapture = capture
        inputMonitoringGranted = SystemInputPermissions().inputMonitoringGranted
        capture.start()
    }

    /// A permission changed: take the hotkeys again so the tap fallback follows the grant.
    /// A paused app stays released.
    private func restartInputCapture(reason: String) {
        guard !paused else { return }
        inputCapture?.restart(reason: reason)
    }

    /// Runs the hold/repeat timer only while a key is down or a tap press awaits Carbon's confirmation.
    private func setInputTicking(_ needed: Bool) {
        inputTimer?.invalidate()
        inputTimer = nil
        guard needed else { return }
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputCapture?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        inputTimer = timer
    }

    private func refreshInputStatus() {
        guard let capture = inputCapture else { return }
        let status = capture.status()

        inputMenu.removeAllItems()
        inputMenu.addItem(disabledItem(status.headline))
        inputMenu.addItem(.separator())
        for line in status.summaryLines { inputMenu.addItem(disabledItem(line)) }
        if !status.problems.isEmpty {
            inputMenu.addItem(.separator())
            for problem in status.problems { inputMenu.addItem(disabledItem("Problem: \(problem.cause)")) }
        }
        let hotkeys = NSMenuItem(title: "Hotkeys", action: nil, keyEquivalent: "")
        let hotkeyMenu = NSMenu()
        for hotkey in status.hotkeys { hotkeyMenu.addItem(disabledItem(status.hotkeyLine(hotkey))) }
        hotkeys.submenu = hotkeyMenu
        inputMenu.addItem(.separator())
        inputMenu.addItem(hotkeys)
        inputMenu.addItem(makeItem("Copy Input Diagnostics", #selector(copyInputDiagnostics)))

        if status.running, let problem = status.problems.first {
            inputProblemItem.title = "Input: " + Self.oneLine(problem.cause)
            inputProblemItem.toolTip = status.headline
            inputProblemItem.isHidden = false
        } else {
            inputProblemItem.isHidden = true
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func oneLine(_ text: String, limit: Int = 100) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    @objc private func copyInputDiagnostics() {
        // Read-only, like Copy Diagnostics: writes only the clipboard.
        guard let capture = inputCapture else { return }
        let logText = (try? String(contentsOf: ActionLog.live.fileURL, encoding: .utf8)) ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(capture.status().render(logText: logText), forType: .string)
        ActionLog.live.write("input: diagnostics copied to clipboard")
    }

    private func refreshCrashReports() {
        crashMenu.removeAllItems()
        let reports = DiagnosticsCollector.recentCrashReports()
        if reports.isEmpty {
            crashMenu.addItem(NSMenuItem(title: "None found", action: nil, keyEquivalent: ""))
            return
        }
        for url in reports {
            let item = makeItem(url.lastPathComponent, #selector(revealCrashReport(_:)))
            item.representedObject = url
            crashMenu.addItem(item)
        }
    }

    @objc private func revealCrashReport(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        ActionLog.live.write("crash report: revealed \(url.lastPathComponent)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func toggleLaunchAtLogin() {
        // Inverse: the same item turns it back off.
        let enable = !LaunchAtLogin.isEnabled
        do {
            try LaunchAtLogin.setEnabled(enable)
            ActionLog.live.write("login item: \(enable ? "enabled" : "disabled")")
            if enable && LaunchAtLogin.needsApproval {
                ActionLog.live.write("login item: waiting for approval in Login Items")
                LaunchAtLogin.openApprovalSettings()
            }
        } catch {
            ActionLog.live.write("login item: \(enable ? "enable" : "disable") failed: \(error.localizedDescription)")
            NSAlert(error: error).runModal()
        }
        refresh()
    }
}
