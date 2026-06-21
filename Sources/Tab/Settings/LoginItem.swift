import ServiceManagement

/// Launch-at-login backed by `SMAppService`. The pane reads `status` as the real
/// source of truth rather than assuming the toggle's value took effect.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// Registers/unregisters the main app. Returns the resulting error (if any)
    /// so the UI can surface a real failure instead of silently lying.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Error? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return nil
        } catch {
            return error
        }
    }
}
