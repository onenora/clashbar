import Foundation

enum RuntimeVisualStatus {
    case stopped
    case starting
    case runningHealthy
    case runningDegraded
    case failed
}

enum StartTrigger {
    case manual
    case auto
}

enum CoreActionState {
    case idle
    case starting
    case stopping
    case restarting
}

enum ConfigLogLevel: String, CaseIterable {
    case silent
    case error
    case warning
    case info
    case debug
}

enum ConfigPatchValue: Sendable {
    case bool(Bool)
    case int(Int)
    case string(String)

    var jsonValue: JSONValue {
        switch self {
        case let .bool(value):
            return .bool(value)
        case let .int(value):
            return .int(value)
        case let .string(value):
            return .string(value)
        }
    }
}

enum StatusBarDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly = "icon_only"
    case iconAndSpeed = "icon_and_speed"
    case speedOnly = "speed_only"

    var id: String { rawValue }
}

enum MenuPanelTabHint: Equatable {
    case proxy
    case rules
    case activity
    case logs
    case system
}

struct DataAcquisitionPolicy: Equatable {
    let enableTrafficStream: Bool
    let enableMemoryStream: Bool
    let enableConnectionsStream: Bool
    let connectionsIntervalMilliseconds: Int?
    let enableLogsStream: Bool
    let mediumFrequencyIntervalNanoseconds: UInt64
    let lowFrequencyIntervalNanoseconds: UInt64
}

enum ProviderRefreshTrigger {
    case start
    case restart
    case configSwitch
}

enum ProviderRefreshPhase {
    case idle
    case updating
    case succeeded
    case failed
    case cancelled
}

struct ProviderRefreshStatus {
    let phase: ProviderRefreshPhase
    let trigger: ProviderRefreshTrigger?
    let progressDone: Int
    let progressTotal: Int
    let message: String?
    let updatedAt: Date?

    static let idle = ProviderRefreshStatus(
        phase: .idle,
        trigger: nil,
        progressDone: 0,
        progressTotal: 0,
        message: nil,
        updatedAt: nil
    )
}

struct ProviderNodeKey: Hashable {
    let provider: String
    let node: String
}

struct MenuBarSpeedLines: Equatable {
    let up: String
    let down: String

    static let zero = MenuBarSpeedLines(up: "↑0B", down: "↓0B")
}

struct MenuBarDisplay: Equatable {
    let mode: StatusBarDisplayMode
    let symbolName: String?
    let speedLines: MenuBarSpeedLines?
}

struct EditableSettingsSnapshot: Equatable, Codable {
    let allowLan: Bool
    let ipv6: Bool
    let unifiedDelay: Bool
    let logLevel: String
    let port: String
    let socksPort: String
    let mixedPort: String
    let redirPort: String
    let tproxyPort: String

    init(config: ConfigSnapshot) {
        allowLan = config.allowLan ?? false
        ipv6 = config.ipv6 ?? false
        unifiedDelay = config.unifiedDelay ?? false
        logLevel = ConfigLogLevel(rawValue: config.logLevel ?? "")?.rawValue ?? ConfigLogLevel.info.rawValue
        port = config.port.map(String.init) ?? ""
        socksPort = config.socksPort.map(String.init) ?? ""
        mixedPort = config.mixedPort.map(String.init) ?? ""
        redirPort = config.redirPort.map(String.init) ?? ""
        tproxyPort = config.tproxyPort.map(String.init) ?? ""
    }

    init(
        allowLan: Bool,
        ipv6: Bool,
        unifiedDelay: Bool,
        logLevel: String,
        port: String,
        socksPort: String,
        mixedPort: String,
        redirPort: String,
        tproxyPort: String
    ) {
        self.allowLan = allowLan
        self.ipv6 = ipv6
        self.unifiedDelay = unifiedDelay
        self.logLevel = logLevel
        self.port = port
        self.socksPort = socksPort
        self.mixedPort = mixedPort
        self.redirPort = redirPort
        self.tproxyPort = tproxyPort
    }
}

struct SystemProxyPorts: Equatable, Sendable {
    let httpPort: Int?
    let httpsPort: Int?
    let socksPort: Int?

    static let disabled = SystemProxyPorts(httpPort: nil, httpsPort: nil, socksPort: nil)

    var hasEnabledPort: Bool {
        httpPort != nil || httpsPort != nil || socksPort != nil
    }

    var primaryPort: Int? {
        httpPort ?? httpsPort ?? socksPort
    }
}
