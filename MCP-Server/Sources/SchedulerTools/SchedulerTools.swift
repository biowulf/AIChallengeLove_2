import Foundation
import MCP
import GitTools

// ═══════════════════════════════════════════════════════════
// MARK: - Tool Definitions
// ═══════════════════════════════════════════════════════════

public enum SchedulerToolDefs {

    /// Напоминание о погоде — повторяющееся или одноразовое.
    public static let remindWeather = Tool(
        name: "remind_weather",
        description: "Напоминать о погоде в городе. Укажи city и одно из: every_minutes (повторять каждые N минут) или in_minutes (один раз через N минут). Чтобы отменить — скажи 'отмени напоминание о погоде'.",
        inputSchema: .object([
            "type": GCType.object,
            "properties": .object([
                "city": .object([
                    "type":        GCType.string,
                    "description": .string("Город. Примеры: Новосибирск, Москва, London")
                ]),
                "every_minutes": .object([
                    "type":        GCType.number,
                    "description": .string("Повторять каждые N минут. Минимум 1. Пример: 2")
                ]),
                "in_minutes": .object([
                    "type":        GCType.number,
                    "description": .string("Напомнить один раз через N минут. Пример: 10")
                ])
            ]),
            "required": .array([.string("city")])
        ])
    )

    /// Отмена напоминания о погоде.
    public static let stopWeather = Tool(
        name: "stop_weather",
        description: "Отменить напоминание о погоде для города. Если city не указан — отменяет все напоминания о погоде.",
        inputSchema: .object([
            "type": GCType.object,
            "properties": .object([
                "city": .object([
                    "type":        GCType.string,
                    "description": .string("Город напоминания которое нужно отменить. Если не указан — отменяются все.")
                ])
            ])
        ])
    )

    public static let all: [Tool] = [remindWeather, stopWeather]
}

// ═══════════════════════════════════════════════════════════
// MARK: - Handler
// ═══════════════════════════════════════════════════════════

public func handleSchedulerToolCall(
    name: String,
    arguments: [String: Value]?,
    scheduler: SchedulerService,
    dataStore: DataStore
) async throws -> CallTool.Result {
    switch name {
    case "remind_weather": return try await handleRemindWeather(arguments, scheduler: scheduler)
    case "stop_weather":   return try await handleStopWeather(arguments, scheduler: scheduler)
    default:               throw MCPError.invalidParams("Unknown scheduler tool: \(name)")
    }
}

// ─── remind_weather ───────────────────────────────────────

private func handleRemindWeather(_ args: [String: Value]?, scheduler: SchedulerService) async throws -> CallTool.Result {
    guard let city = asString(args?["city"]), !city.isEmpty else {
        throw MCPError.invalidParams("Укажи город: city='Новосибирск'")
    }

    let everyMin = asInt(args?["every_minutes"])
    let inMin    = asInt(args?["in_minutes"])

    guard everyMin != nil || inMin != nil else {
        throw MCPError.invalidParams("Укажи every_minutes (повторять каждые N минут) или in_minutes (один раз через N минут)")
    }

    let config = "{\"city\":\"\(city.jsonEscaped)\"}"
    let jobID  = "weather-\(city.lowercased().replacingOccurrences(of: " ", with: "-"))"

    if let interval = everyMin, interval >= 1 {
        try await scheduler.scheduleJob(id: jobID, source: .weather,
                                         intervalSec: interval * 60, config: config)
        return .init(content: [.text("{\"status\":\"ok\",\"mode\":\"repeat\",\"city\":\"\(city.jsonEscaped)\",\"every_minutes\":\(interval)}")])
    } else if let delay = inMin, delay >= 1 {
        let remID = "\(jobID)-once"
        try await scheduler.addReminder(id: remID, text: "weather:\(city)", delaySeconds: delay * 60)
        return .init(content: [.text("{\"status\":\"ok\",\"mode\":\"once\",\"city\":\"\(city.jsonEscaped)\",\"in_minutes\":\(delay)}")])
    } else {
        throw MCPError.invalidParams("every_minutes и in_minutes должны быть >= 1")
    }
}

// ─── stop_weather ─────────────────────────────────────────

private func handleStopWeather(_ args: [String: Value]?, scheduler: SchedulerService) async throws -> CallTool.Result {
    let city = asString(args?["city"])

    if let city, !city.isEmpty {
        let jobID = "weather-\(city.lowercased().replacingOccurrences(of: " ", with: "-"))"
        try? await scheduler.stopJob(id: jobID)
        return .init(content: [.text("{\"status\":\"stopped\",\"city\":\"\(city.jsonEscaped)\"}")])
    } else {
        // Остановить все weather-джобы
        let allIDs = await scheduler.listJobIDs()
        for id in allIDs where id.hasPrefix("weather-") {
            try? await scheduler.stopJob(id: id)
        }
        return .init(content: [.text("{\"status\":\"all_stopped\"}")])
    }
}


// ═══════════════════════════════════════════════════════════
// MARK: - Value helpers
// ═══════════════════════════════════════════════════════════

/// Извлекает Int из Value независимо от того, хранится ли он как .int, .double или .string.
/// SDK-версия Value.intValue возвращает nil для .string — этот хелпер решает проблему.
private func asInt(_ v: Value?) -> Int? {
    guard let v else { return nil }
    switch v {
    case .int(let i):    return i
    case .double(let d): return Int(d)
    case .string(let s): return Int(s)
    default:             return nil
    }
}

/// Извлекает String из Value (.string или число → строка).
private func asString(_ v: Value?) -> String? {
    guard let v else { return nil }
    switch v {
    case .string(let s): return s
    case .int(let i):    return String(i)
    case .double(let d): return String(d)
    default:             return nil
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - JSON helper
// ═══════════════════════════════════════════════════════════

private func jsonString(_ dict: [String: String]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
          let str = String(data: data, encoding: .utf8)
    else { return "{}" }
    return str
}
