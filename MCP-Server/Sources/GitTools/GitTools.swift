import Foundation
import MCP

// ═══════════════════════════════════════════════════════════
// MARK: - GigaChat-совместимые типы параметров
// ═══════════════════════════════════════════════════════════

/// Типы параметров функций, которые принимает GigaChat.
/// Источник: https://developers.sber.ru/docs/ru/gigachat/api/reference/rest/post-chat
///
/// Поддерживаются: string, number, boolean, object, array.
/// НЕ поддерживается: integer — GigaChat вернёт 500.
public enum GCType {
    public static let string  = Value.string("string")
    public static let number  = Value.string("number")   // целые и дробные числа
    public static let boolean = Value.string("boolean")
    public static let object  = Value.string("object")
    public static let array   = Value.string("array")
}

// ═══════════════════════════════════════════════════════════
// MARK: - Open-Meteo API Response Models (private)
// ═══════════════════════════════════════════════════════════

private struct GeocodingResponse: Decodable {
    let results: [GeocodingResult]?
}

private struct GeocodingResult: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
}

private struct WeatherResponse: Decodable {
    let current: CurrentWeather
    enum CodingKeys: String, CodingKey { case current }
}

private struct CurrentWeather: Decodable {
    let time: String
    let temperature2m: Double
    let relativeHumidity2m: Int
    let windSpeed10m: Double
    let precipitation: Double
    let weatherCode: Int

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m      = "temperature_2m"
        case relativeHumidity2m = "relative_humidity_2m"
        case windSpeed10m       = "wind_speed_10m"
        case precipitation
        case weatherCode        = "weather_code"
    }
}

private struct ForecastResponse: Decodable {
    let daily: DailyWeather
}

private struct DailyWeather: Decodable {
    let time: [String]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]
    let relativeHumidity2mMean: [Int?]?
    let windSpeed10mMax: [Double?]
    let precipitationSum: [Double?]
    let weatherCode: [Int?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2mMax        = "temperature_2m_max"
        case temperature2mMin        = "temperature_2m_min"
        case relativeHumidity2mMean  = "relative_humidity_2m_mean"
        case windSpeed10mMax         = "wind_speed_10m_max"
        case precipitationSum        = "precipitation_sum"
        case weatherCode             = "weather_code"
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - WMO Weather Code → Description
// ═══════════════════════════════════════════════════════════

private func weatherDescription(for code: Int) -> String {
    switch code {
    case 0:       return "Ясно"
    case 1:       return "В основном ясно"
    case 2:       return "Переменная облачность"
    case 3:       return "Пасмурно"
    case 45, 48:  return "Туман"
    case 51:      return "Лёгкая морось"
    case 53:      return "Умеренная морось"
    case 55:      return "Сильная морось"
    case 61:      return "Лёгкий дождь"
    case 63:      return "Умеренный дождь"
    case 65:      return "Сильный дождь"
    case 71:      return "Лёгкий снег"
    case 73:      return "Умеренный снег"
    case 75:      return "Сильный снег"
    case 80:      return "Небольшой ливень"
    case 81:      return "Умеренный ливень"
    case 82:      return "Сильный ливень"
    case 95:      return "Гроза"
    case 96, 99:  return "Гроза с градом"
    default:      return "Переменная погода (код \(code))"
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - Tool Definition
// ═══════════════════════════════════════════════════════════

public enum WeatherToolDefs {
    public static let getWeather = Tool(
        name: "get_weather",
        description: """
            Возвращает реальную погоду для города на указанную дату. \
            Вызывай каждый раз, когда нужны погодные данные — температура, ветер, осадки. \
            Для нескольких дней вызывай по одному разу на каждый день. \
            Параметр date — один день в формате YYYY-MM-DD. \
            Когда пользователь называет день относительно («в субботу», «на выходных», «завтра») — сначала вызови get_current_date, чтобы узнать текущую дату.
            """,
        inputSchema: .object([
            "type": GCType.object,
            "properties": .object([
                "location": .object([
                    "type":        GCType.string,
                    "description": .string("Название города или местоположения, например: Москва, London, Новосибирск")
                ]),
                "date": .object([
                    "type":        GCType.string,
                    "description": .string("ОДИН день в строгом формате YYYY-MM-DD. Любые диапазоны , слэши, запятые — недопустимы. Передавай ровно одну дату.")
                ])
            ]),
            "required": .array([.string("location")])
        ])
    )

    public static let all: [Tool] = [getWeather]
}

// ═══════════════════════════════════════════════════════════
// MARK: - Date Tool Definition
// ═══════════════════════════════════════════════════════════

public enum DateToolDefs {
    public static let getCurrentDate = Tool(
        name: "get_current_date",
        description: "Возвращает сегодняшнюю дату и день недели. Вызывай первым когда пользователь упоминает относительные даты: «завтра», «в субботу», «на выходных», «на следующей неделе» — текущую дату нельзя узнать без этого инструмента.",
        inputSchema: .object([
            "type":       GCType.object,
            "properties": .object([:]),
            "required":   .array([])
        ])
    )

    public static let all: [Tool] = [getCurrentDate]
}

// ═══════════════════════════════════════════════════════════
// MARK: - Tool Handler
// ═══════════════════════════════════════════════════════════

public func handleToolCall(name: String, arguments: [String: Value]?) async throws -> CallTool.Result {
    switch name {
    case "get_weather":
        return try await handleGetWeather(arguments)
    case "get_current_date":
        return handleGetCurrentDate()
    default:
        throw MCPError.invalidParams("Unknown tool: \(name)")
    }
}

private func handleGetCurrentDate() -> CallTool.Result {
    let now = Date()

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")

    let weekdayFormatter = DateFormatter()
    weekdayFormatter.dateFormat = "EEEE"
    weekdayFormatter.locale = Locale(identifier: "ru_RU")

    let date    = dateFormatter.string(from: now)
    let weekday = weekdayFormatter.string(from: now).capitalized

    return CallTool.Result(content: [.text("\(date) (\(weekday))")])
}

private func handleGetWeather(_ args: [String: Value]?) async throws -> CallTool.Result {
    guard let location = args?["location"]?.stringValue, !location.isEmpty else {
        throw MCPError.invalidParams("'location' is required")
    }
    // Валидируем date: строго YYYY-MM-DD, никаких диапазонов
    let rawDate = args?["date"]?.stringValue
    let dateRegex = /^\d{4}-\d{2}-\d{2}$/
    let date: String?
    if let raw = rawDate {
        guard raw.wholeMatch(of: dateRegex) != nil else {
            return CallTool.Result(content: [.text("Неверный формат даты: '\(raw)'. Ожидается строго YYYY-MM-DD, например 2026-03-21. Диапазоны дат недопустимы.")])
        }
        date = raw
    } else {
        date = nil
    }

    // 1. Геокодинг через Open-Meteo Geocoding API
    guard let encodedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encodedLocation)&count=1&language=ru&format=json") else {
        throw MCPError.invalidParams("Невалидное местоположение: \(location)")
    }

    let (geoData, _) = try await URLSession.shared.data(from: geoURL)
    let geoResponse = try JSONDecoder().decode(GeocodingResponse.self, from: geoData)

    guard let geo = geoResponse.results?.first else {
        return CallTool.Result(content: [.text("Город '\(location)' не найден.")])
    }

    let parts = [geo.name, geo.admin1 ?? "", geo.country ?? ""].filter { !$0.isEmpty }
    let place = parts.joined(separator: ", ")

    if let date {
        // 2a. Прогноз на конкретный день (daily forecast)
        let weatherURLStr = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(geo.latitude)&longitude=\(geo.longitude)"
            + "&daily=temperature_2m_max,temperature_2m_min,wind_speed_10m_max,precipitation_sum,weather_code"
            + "&start_date=\(date)&end_date=\(date)"
            + "&wind_speed_unit=ms&timezone=auto"

        guard let weatherURL = URL(string: weatherURLStr) else {
            throw MCPError.invalidParams("Не удалось сформировать URL погоды")
        }

        let (weatherData, _) = try await URLSession.shared.data(from: weatherURL)
        let forecast = try JSONDecoder().decode(ForecastResponse.self, from: weatherData)
        let daily = forecast.daily

        guard let idx = daily.time.firstIndex(of: date) else {
            return CallTool.Result(content: [.text("Нет данных прогноза для даты \(date)")])
        }

        let tempMax  = daily.temperature2mMax[idx] ?? 0
        let tempMin  = daily.temperature2mMin[idx] ?? 0
        let tempAvg  = (tempMax + tempMin) / 2
        let wind     = daily.windSpeed10mMax[idx] ?? 0
        let precip   = daily.precipitationSum[idx] ?? 0
        let code     = daily.weatherCode[idx] ?? 0
        let cond     = weatherDescription(for: code)

        // precipitation label
        let precipLabel: String
        switch precip {
        case 0:        precipLabel = "none"
        case 0..<2:    precipLabel = "light rain"
        case 2..<10:   precipLabel = "rain"
        default:       precipLabel = "heavy rain"
        }

        let payload: [String: Any] = [
            "location":          place,
            "day":               date,
            "temperature":       round(tempAvg * 10) / 10,
            "temperature_max":   tempMax,
            "temperature_min":   tempMin,
            "wind":              wind,
            "precipitation":     precipLabel,
            "precipitation_mm":  precip,
            "humidity":          0,   // daily endpoint не возвращает humidity без hourly
            "condition":         cond,
            "weather_code":      code
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(jsonString)])

    } else {
        // 2b. Текущая погода (прежнее поведение)
        let weatherURLStr = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(geo.latitude)&longitude=\(geo.longitude)"
            + "&current=temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation,weather_code"
            + "&wind_speed_unit=ms&timezone=auto"

        guard let weatherURL = URL(string: weatherURLStr) else {
            throw MCPError.invalidParams("Не удалось сформировать URL погоды")
        }

        let (weatherData, _) = try await URLSession.shared.data(from: weatherURL)
        let weather = try JSONDecoder().decode(WeatherResponse.self, from: weatherData)
        let cur = weather.current
        let condition = weatherDescription(for: cur.weatherCode)

        let payload: [String: Any] = [
            "location":          place,
            "temperature_c":     cur.temperature2m,
            "humidity_percent":  cur.relativeHumidity2m,
            "wind_speed_ms":     cur.windSpeed10m,
            "precipitation_mm":  cur.precipitation,
            "condition":         condition,
            "weather_code":      cur.weatherCode,
            "time":              cur.time
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(jsonString)])
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - Server Factory + Registration
// ═══════════════════════════════════════════════════════════

public func createMCPServer() -> Server {
    Server(
        name: "swift-weather-mcp",
        version: "1.0.0",
        capabilities: .init(tools: .init(listChanged: false))
    )
}

public func registerToolHandlers(on server: Server) async {
    await server.withMethodHandler(ListTools.self) { _ in
        ListTools.Result(tools: WeatherToolDefs.all)
    }

    await server.withMethodHandler(CallTool.self) { params in
        try await handleToolCall(name: params.name, arguments: params.arguments)
    }
}
