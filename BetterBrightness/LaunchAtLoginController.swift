import Combine
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct MainAppLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// macOS owns this preference; do not mirror it in UserDefaults or register on launch.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var status: SMAppService.Status

    private let service: any LoginItemService

    init(service: (any LoginItemService)? = nil) {
        let service = service ?? MainAppLoginItemService()
        self.service = service
        status = service.status
    }

    var isRequested: Bool {
        status == .enabled || status == .requiresApproval
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) throws {
        refresh()
        guard enabled != isRequested else { return }
        defer { refresh() }

        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
