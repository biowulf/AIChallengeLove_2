import Foundation

// ═══════════════════════════════════════════════════════════
// MARK: - Data Source
// ═══════════════════════════════════════════════════════════

public enum DataSource: String, Sendable, Codable {
    case weather   = "weather"
    case customURL = "custom_url"
}

// ═══════════════════════════════════════════════════════════
// MARK: - Scheduled Job
// ═══════════════════════════════════════════════════════════

public struct ScheduledJob: Sendable {
    public let id: String
    public let source: DataSource
    public let intervalSec: Int
    public let config: String   // JSON: {"city":"Moscow"} | {"url":"https://..."}

    public init(id: String, source: DataSource, intervalSec: Int, config: String) {
        self.id = id
        self.source = source
        self.intervalSec = intervalSec
        self.config = config
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - Collected Data Record
// ═══════════════════════════════════════════════════════════

public struct DataRecord: Sendable {
    public let id: String
    public let source: String
    public let timestamp: Date
    public let payload: String  // raw JSON text

    public init(id: String, source: String, timestamp: Date, payload: String) {
        self.id = id
        self.source = source
        self.timestamp = timestamp
        self.payload = payload
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - Reminder
// ═══════════════════════════════════════════════════════════

public struct Reminder: Sendable {
    public let id: String
    public let text: String
    public let fireAt: Date
    public let fired: Bool

    public init(id: String, text: String, fireAt: Date, fired: Bool = false) {
        self.id = id
        self.text = text
        self.fireAt = fireAt
        self.fired = fired
    }
}
