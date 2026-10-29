import Foundation
import ServiceManagement

@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var failure: Error?
    var registerCalls = 0
    var unregisterCalls = 0

    func register() throws {
        registerCalls += 1
        if let failure { throw failure }
        status = registrationStatus
    }

    func unregister() throws {
        unregisterCalls += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

@main
struct LaunchAtLoginTests {
    @MainActor
    static func main() throws {
        let service = FakeLoginItemService()
        let controller = LaunchAtLoginController(service: service)
        precondition(!controller.isRequested)
        precondition(service.registerCalls == 0 && service.unregisterCalls == 0,
                     "Reading the preference must never register the app")

        try controller.setEnabled(true)
        precondition(controller.status == .enabled && controller.isRequested)
        try controller.setEnabled(true)
        precondition(service.registerCalls == 1)
        try controller.setEnabled(false)
        precondition(controller.status == .notRegistered && !controller.isRequested)
        print("PASS: opt-in registration, duplicate requests and disabling")

        service.registrationStatus = .requiresApproval
        try controller.setEnabled(true)
        precondition(controller.status == .requiresApproval && controller.isRequested)
        try controller.setEnabled(false)
        precondition(controller.status == .notRegistered && !controller.isRequested)
        print("PASS: pending approval stays distinguishable and can be cancelled")

        service.status = .enabled
        controller.refresh()
        precondition(controller.status == .enabled)
        service.status = .notRegistered
        try controller.setEnabled(true)
        precondition(service.registerCalls == 3,
                     "Refresh external changes before acting on a stale view")
        service.status = .enabled
        controller.refresh()
        precondition(controller.status == .enabled)
        print("PASS: changes made in System Settings are reflected")

        service.failure = NSError(domain: "LoginItemTest", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
        do {
            try controller.setEnabled(false)
            preconditionFailure("Unregister failure must reach the caller")
        } catch {
            precondition(controller.status == .enabled && controller.isRequested)
        }
        service.status = .notRegistered
        do {
            try controller.setEnabled(true)
            preconditionFailure("Register failure must reach the caller")
        } catch {
            precondition(controller.status == .notRegistered && !controller.isRequested)
        }
        service.status = .notFound
        controller.refresh()
        precondition(controller.status == .notFound && !controller.isRequested)
        print("PASS: failures retain the actual macOS state; unavailable is not enabled")
    }
}
