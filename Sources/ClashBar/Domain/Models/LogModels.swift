import Foundation

struct AppErrorLogEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: String
    let message: String

    init(id: UUID = UUID(), timestamp: Date = Date(), level: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

struct LogsResponse: Codable, Equatable {
    let logs: [LogLine]?
}

struct LogLine: Codable, Equatable {
    let type: String?
    let payload: String?
}

struct DelayMeasurement: Codable, Equatable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let map = try? container.decode([String: Int].self) {
            value = map.values.first
        } else {
            value = nil
        }
    }
}

struct GroupDelayMeasurement: Codable, Equatable {
    let values: [String: Int]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = (try? container.decode([String: Int].self)) ?? [:]
    }
}
