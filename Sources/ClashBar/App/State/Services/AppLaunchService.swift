import Foundation
import ServiceManagement

enum AppLaunchServiceError: Error {
    case unsupportedEnvironment
    case requiresApproval
    case registrationFailed(String)
    case unregistrationFailed(String)
}

struct AppLaunchService {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isRunningFromAppBundle else {
            throw AppLaunchServiceError.unsupportedEnvironment
        }

        if enabled {
            do {
                try service.register()
            } catch {
                throw AppLaunchServiceError.registrationFailed(error.localizedDescription)
            }

            let status = service.status
            if status == .enabled { return }
            if status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                throw AppLaunchServiceError.requiresApproval
            }
            throw AppLaunchServiceError.registrationFailed("status=\(status.rawValue)")
        } else {
            do {
                try service.unregister()
            } catch {
                throw AppLaunchServiceError.unregistrationFailed(error.localizedDescription)
            }

            if service.status == .enabled {
                throw AppLaunchServiceError.unregistrationFailed("status=\(service.status.rawValue)")
            }
        }
    }

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}
