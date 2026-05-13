import ServiceManagement

enum LoginItemState: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var menuTitle: String {
        switch self {
        case .requiresApproval, .unavailable:
            return "Launch at Login…"
        case .enabled, .disabled:
            return "Launch at Login"
        }
    }

    var isChecked: Bool {
        self == .enabled
    }
}

protocol LoginItemControlling {
    func state() -> LoginItemState
    func setEnabled(_ isEnabled: Bool) throws
}

struct SystemLoginItemController: LoginItemControlling {
    func state() -> LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

protocol LoginItemsSettingsLaunching {
    func openLoginItemsSettings() -> Bool
}

struct SystemLoginItemsSettingsLauncher: LoginItemsSettingsLaunching {
    func openLoginItemsSettings() -> Bool {
        SMAppService.openSystemSettingsLoginItems()
        return true
    }
}
