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
        description: "Получить текущую погоду для указанного города. Возвращает температуру, влажность, скорость ветра и описание погоды.",
        inputSchema: .object([
            "type": GCType.object,
            "properties": .object([
                "location": .object([
                    "type":        GCType.string,
                    "description": .string("Название города или местоположения, например: Москва, London, New York")
                ])
            ]),
            "required": .array([.string("location")])
        ])
    )

    public static let all: [Tool] = [getWeather]
}

// ═══════════════════════════════════════════════════════════
// MARK: - Value helpers
// ═══════════════════════════════════════════════════════════

extension Value {
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - Tool Handler
// ═══════════════════════════════════════════════════════════

public func handleToolCall(name: String, arguments: [String: Value]?) async throws -> CallTool.Result {
    switch name {
    case "get_weather":
        return try await handleGetWeather(arguments)
    default:
        throw MCPError.invalidParams("Unknown tool: \(name)")
    }
}

private func handleGetWeather(_ args: [String: Value]?) async throws -> CallTool.Result {
    guard let location = args?["location"]?.stringValue, !location.isEmpty else {
        throw MCPError.invalidParams("'location' is required")
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

    // 2. Прогноз погоды через Open-Meteo Forecast API
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

    // 3. Возвращаем структурированный JSON — ИИ сам сформирует ответ пользователю
    let parts = [geo.name, geo.admin1 ?? "", geo.country ?? ""].filter { !$0.isEmpty }
    let place = parts.joined(separator: ", ")
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
