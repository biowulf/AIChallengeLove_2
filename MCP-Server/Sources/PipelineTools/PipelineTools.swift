import Foundation
import MCP
import GitTools

// ═══════════════════════════════════════════════════════════
// MARK: - Tool Definitions
// ═══════════════════════════════════════════════════════════

public enum PipelineToolDefs {

    /// Сравнивает погодные условия за несколько дней и определяет лучший для активности на улице.
    public static let compareConditions = Tool(
        name: "compare_conditions",
        description: """
            Сравнивает погодные условия за несколько дней и определяет лучший для активности на улице. \
            Вызывай после того как получил погоду за все нужные дни через get_weather. \
            В массив conditions включи по одному объекту на каждый день: \
            day — поле day из ответа get_weather, \
            temperature — поле temperature из ответа get_weather, \
            wind — поле wind из ответа get_weather, \
            precipitation — поле precipitation из ответа get_weather, \
            humidity — поле humidity из ответа get_weather.
            """,
        inputSchema: .object([
            "type": GCType.object,
            "properties": .object([
                "conditions": .object([
                    "type": .string("array"),
                    "description": .string("Массив объектов с погодными условиями — по одному на каждый день из результатов get_weather."),
                    "items": .object([
                        "type": GCType.object,
                        "properties": .object([
                            "day":           .object(["type": GCType.string, "description": .string("Дата в формате YYYY-MM-DD, поле day из ответа get_weather")]),
                            "temperature":   .object(["type": GCType.number, "description": .string("Средняя температура °C, поле temperature из ответа get_weather")]),
                            "wind":          .object(["type": GCType.number, "description": .string("Скорость ветра м/с, поле wind из ответа get_weather")]),
                            "precipitation": .object(["type": GCType.string, "description": .string("Осадки: none/light rain/rain/heavy rain/snow, поле precipitation из ответа get_weather")]),
                            "humidity":      .object(["type": GCType.number, "description": .string("Влажность %, поле humidity из ответа get_weather")])
                        ])
                    ])
                ])
            ]),
            "required": .array([.string("conditions")])
        ])
    )

    /// Подбирает рекомендации по одежде исходя из погодных условий и активности.
    public static let getClothingAdvice = Tool(
        name: "get_clothing_advice",
        description: """
            Подбирает рекомендации по одежде исходя из погодных условий и активности. \
            Вызывай когда пользователь спрашивает, что надеть, или упоминает конкретную активность (велосипед, бег, поход, прогулка). \
            Передай temperature, wind, precipitation из результата get_weather для выбранного дня. \
            activity: cycling — велосипед, running — бег, hiking — поход, walking — прогулка.
            """,
        inputSchema: .object([
            "type": GCType.object,
            "properties": .object([
                "temperature": .object([
                    "type":        GCType.number,
                    "description": .string("Температура воздуха в градусах Цельсия")
                ]),
                "wind": .object([
                    "type":        GCType.number,
                    "description": .string("Скорость ветра в м/с")
                ]),
                "precipitation": .object([
                    "type":        GCType.string,
                    "description": .string("Осадки: none, light rain, rain, heavy rain, snow")
                ]),
                "activity": .object([
                    "type":        GCType.string,
                    "description": .string("Тип активности: cycling, running, hiking, walking, или другой. По умолчанию — walking.")
                ])
            ]),
            "required": .array([.string("temperature"), .string("wind"), .string("precipitation")])
        ])
    )

    public static let all: [Tool] = [compareConditions, getClothingAdvice]
}

// ═══════════════════════════════════════════════════════════
// MARK: - Handler
// ═══════════════════════════════════════════════════════════

public func handlePipelineToolCall(
    name: String,
    arguments: [String: Value]?
) async throws -> CallTool.Result {
    switch name {
    case "compare_conditions":  return try handleCompareConditions(arguments)
    case "get_clothing_advice": return try handleGetClothingAdvice(arguments)
    default:                    throw MCPError.invalidParams("Unknown pipeline tool: \(name)")
    }
}

// ─── compare_conditions ───────────────────────────────────

private func handleCompareConditions(_ args: [String: Value]?) throws -> CallTool.Result {
    print("🔍 compare_conditions args: \(args as Any)")
    guard let conditionsValue = args?["conditions"],
          case .array(let items) = conditionsValue,
          !items.isEmpty else {
        print("❌ compare_conditions: conditions missing or empty. args keys: \(args?.keys.joined(separator: ", ") ?? "nil")")
        throw MCPError.invalidParams("'conditions' array is required and must not be empty")
    }

    struct DayScore {
        let day: String
        let temp: Double
        let wind: Double
        let precip: String
        let score: Int
        let reasons: [String]
    }

    var scores: [DayScore] = []

    for item in items {
        guard case .object(let obj) = item else { continue }

        let day   = asString(obj["day"]) ?? asString(obj["date"]) ?? "Unknown"
        let temp  = asDouble(obj["temperature"]) ?? asDouble(obj["temperature_c"]) ?? 0
        let wind  = asDouble(obj["wind"]) ?? asDouble(obj["wind_speed_ms"]) ?? 0
        let precip = asString(obj["precipitation"])
            ?? (asDouble(obj["precipitation_mm"]) ?? 0 > 0 ? "rain" : "none")

        var score = 0
        var reasons: [String] = []

        // Осадки (0–40 баллов)
        switch precip.lowercased() {
        case "none":
            score += 40; reasons.append("нет осадков (+40)")
        case "light rain":
            score += 10; reasons.append("лёгкий дождь (+10)")
        default:
            reasons.append("дождь/снег (+0)")
        }

        // Ветер (0–30 баллов)
        switch wind {
        case ..<3:
            score += 30; reasons.append("слабый ветер \(String(format: "%.1f", wind)) м/с (+30)")
        case 3..<6:
            score += 20; reasons.append("умеренный ветер \(String(format: "%.1f", wind)) м/с (+20)")
        case 6..<10:
            score += 10; reasons.append("ветер \(String(format: "%.1f", wind)) м/с (+10)")
        default:
            reasons.append("сильный ветер \(String(format: "%.1f", wind)) м/с (+0)")
        }

        // Температура (0–30 баллов)
        switch temp {
        case 10...20:
            score += 30; reasons.append("комфортная температура \(String(format: "%.1f", temp))°C (+30)")
        case 5..<10:
            score += 20; reasons.append("прохладно \(String(format: "%.1f", temp))°C (+20)")
        case 0..<5:
            score += 10; reasons.append("холодно \(String(format: "%.1f", temp))°C (+10)")
        default:
            reasons.append("некомфортная температура \(String(format: "%.1f", temp))°C (+0)")
        }

        scores.append(DayScore(day: day, temp: temp, wind: wind, precip: precip,
                               score: score, reasons: reasons))
    }

    guard let best = scores.max(by: { $0.score < $1.score }) else {
        throw MCPError.invalidParams("Could not evaluate conditions")
    }

    // Сортируем по убыванию для сравнения
    let sorted = scores.sorted { $0.score > $1.score }
    var comparisonParts: [String] = []
    for s in sorted {
        comparisonParts.append("\(s.day): \(s.score) баллов (\(s.reasons.joined(separator: ", ")))")
    }

    let reason = best.reasons.joined(separator: "; ")
    let payload: [String: Any] = [
        "bestDay":    best.day,
        "score":      best.score,
        "reason":     reason,
        "comparison": comparisonParts
    ]

    let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
    return CallTool.Result(content: [.text(jsonString)])
}

// ─── get_clothing_advice ──────────────────────────────────

private func handleGetClothingAdvice(_ args: [String: Value]?) throws -> CallTool.Result {
    guard let temp = asDouble(args?["temperature"]) else {
        throw MCPError.invalidParams("'temperature' is required")
    }
    guard let wind = asDouble(args?["wind"]) else {
        throw MCPError.invalidParams("'wind' is required")
    }
    let precipitation = asString(args?["precipitation"]) ?? "none"
    let activity      = asString(args?["activity"])?.lowercased() ?? "walking"

    var layers: [String] = []
    var extras: [String] = []

    let isRain = precipitation.lowercased().contains("rain")
    let isSnow = precipitation.lowercased() == "snow"
    let isWet  = isRain || isSnow
    let isWindy = wind > 5

    // Базовые слои по температуре
    switch temp {
    case 20...:
        layers = ["футболка"]
    case 15..<20:
        layers = ["футболка", "лёгкая куртка или толстовка"]
    case 10..<15:
        layers = ["термобельё (лёгкое)", "флис", "ветровка"]
    case 5..<10:
        layers = ["термобельё", "флис", "утеплённая ветровка"]
    case 0..<5:
        layers = ["термобельё", "флис", "утеплённая куртка"]
    default:
        layers = ["термобельё (плотное)", "флис", "пуховик"]
    }

    // Мокрая погода — мембрана вместо верхнего слоя
    if isWet {
        if layers.count >= 1 {
            layers[layers.count - 1] = isSnow ? "мембранная куртка + непромокаемые штаны" : "мембранная куртка"
        }
        extras.append(isSnow ? "непромокаемые бахилы или ботинки" : "водонепроницаемая обувь")
    }

    // Ветер — добавить ветрозащиту если её нет
    if isWindy && !isWet {
        if !layers.contains(where: { $0.contains("ветровка") || $0.contains("куртка") }) {
            layers.append("ветровка")
        }
    }

    // Активность — корректировки
    switch activity {
    case "cycling":
        if temp < 10 { extras.append("перчатки") }
        if temp < 5  { extras.append("бафф на шею") }
        if temp < 0  { extras.append("балаклава") }
        extras.append("велошлем")
        if isRain { extras.append("дождевые бахилы на велотуфли") }
        // При езде тело греется — убираем один тяжёлый слой если тепло
        if temp >= 10 && layers.count > 2 { layers.removeLast() }

    case "running":
        // Бег генерирует тепло — убираем один слой
        if layers.count > 1 { layers.removeLast() }
        if temp < 5 { extras.append("перчатки") }
        if temp < 0 { extras.append("шапка") }
        if isRain   { extras.append("лёгкий дождевик") }

    case "hiking":
        if temp < 10 { extras.append("перчатки") }
        extras.append("трекинговые ботинки")
        if isRain || isSnow { extras.append("гетры или непромокаемые гамаши") }

    default: // walking и прочее
        if temp < 5  { extras.append("перчатки") }
        if temp < 0  { extras.append("шапка") }
    }

    // Дедупликация
    let uniqueExtras = Array(NSOrderedSet(array: extras)) as! [String]

    let payload: [String: Any] = [
        "layers":   layers,
        "extras":   uniqueExtras,
        "activity": activity,
        "conditions": [
            "temperature":   temp,
            "wind":          wind,
            "precipitation": precipitation
        ]
    ]

    let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
    return CallTool.Result(content: [.text(jsonString)])
}

// ═══════════════════════════════════════════════════════════
// MARK: - Value Helpers
// ═══════════════════════════════════════════════════════════

private func asString(_ v: Value?) -> String? {
    guard let v, case .string(let s) = v else { return nil }
    return s
}

private func asDouble(_ v: Value?) -> Double? {
    guard let v else { return nil }
    switch v {
    case .double(let d): return d
    case .int(let i):    return Double(i)
    case .string(let s): return Double(s)
    default:             return nil
    }
}
