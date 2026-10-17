import ServiceManagement

/// Launch at login through SMAppService. Off until the user turns it on; never registered implicitly.
/// Only meaningful for the packaged .app (see scripts/build-app.sh).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
