import Foundation

// ═══════════════════════════════════════════════════════════
// MARK: - Open-Meteo structs (private)
// ═══════════════════════════════════════════════════════════

private struct GeoResponse: Decodable {
    let results: [GeoResult]?
}
private struct GeoResult: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
}
private struct WeatherResp: Decodable {
    let current: CurrentW
}
private struct CurrentW: Decodable {
    let temperature2m: Double
    let relativeHumidity2m: Int
    let windSpeed10m: Double
    let precipitation: Double
    let weatherCode: Int
    enum CodingKeys: String, CodingKey {
        case temperature2m      = "temperature_2m"
        case relativeHumidity2m = "relative_humidity_2m"
        case windSpeed10m       = "wind_speed_10m"
        case precipitation
        case weatherCode        = "weather_code"
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - SchedulerService
// ═══════════════════════════════════════════════════════════

public actor SchedulerService {

    private var jobTasks: [String: Task<Void, Never>] = [:]
    private let dataStore: DataStore
    private let emitter: EventEmitter

    public init(dataStore: DataStore, emitter: EventEmitter) {
        self.dataStore = dataStore
        self.emitter = emitter
    }

    // ─── Restore on startup ───────────────────────────────

    /// Re-schedules ONLY reminders from SQLite (time-sensitive).
    /// Periodic jobs are NOT auto-restored — they require an explicit `schedule_job` call.
    /// Call once at startup: `await scheduler.restoreReminders()`.
    public func restoreReminders() {
        let reminders = (try? dataStore.loadActiveReminders()) ?? []
        let now = Date()
        for reminder in reminders {
            if reminder.fireAt > now {
                let delay = Int(reminder.fireAt.timeIntervalSinceNow)
                scheduleReminderTask(id: reminder.id, text: reminder.text, delaySeconds: delay)
                log("♻️", "Restored reminder[\(reminder.id)] fires in \(delay)s: \"\(reminder.text)\"")
            } else {
                try? dataStore.markReminderFired(id: reminder.id)
                log("⚠️", "Missed reminder[\(reminder.id)]: \"\(reminder.text)\"")
            }
        }
    }

    /// Re-schedules ALL jobs AND reminders from SQLite (full restore after crash/restart).
    /// Use only if you explicitly want periodic jobs to auto-resume on server restart.
    public func restoreFromDB() {
        // Restore periodic jobs
        let jobs = (try? dataStore.loadScheduledJobs()) ?? []
        for job in jobs {
            startJobTask(job.id, source: job.source, intervalSec: job.intervalSec, config: job.config)
            log("♻️", "Restored job[\(job.id)] source=\(job.source.rawValue) interval=\(job.intervalSec)s")
        }
        // Restore reminders
        restoreReminders()
    }

    // ─── Scheduled Jobs ───────────────────────────────────

    public func scheduleJob(id: String, source: DataSource, intervalSec: Int, config: String) throws {
        // Persist to DB (survives restarts)
        try dataStore.upsertScheduledJob(id: id, source: source.rawValue,
                                          intervalSec: intervalSec, config: config)
        // Cancel existing task with same id, if any
        jobTasks[id]?.cancel()
        startJobTask(id, source: source, intervalSec: intervalSec, config: config)
        log("🚀", "Job[\(id)] scheduled: source=\(source.rawValue) interval=\(intervalSec)s config=\(config)")
    }

    public func stopJob(id: String) throws {
        jobTasks[id]?.cancel()
        jobTasks.removeValue(forKey: id)
        try dataStore.deleteScheduledJob(id: id)
        log("🛑", "Job[\(id)] stopped")
    }

    public func listJobIDs() -> [String] {
        Array(jobTasks.keys)
    }

    // ─── Reminders ────────────────────────────────────────

    public func addReminder(id: String, text: String, delaySeconds: Int) throws {
        let fireAt = Date().addingTimeInterval(Double(delaySeconds))
        try dataStore.insertReminder(id: id, text: text, fireAt: fireAt)
        scheduleReminderTask(id: id, text: text, delaySeconds: delaySeconds)
        log("⏰", "Reminder[\(id)] set: \"\(text)\" fires in \(delaySeconds)s")
    }

    // ─── Private helpers ──────────────────────────────────

    private func startJobTask(_ id: String, source: DataSource, intervalSec: Int, config: String) {
        let task = Task {
            // Collect immediately on first run, then every intervalSec
            repeat {
                if Task.isCancelled { break }
                await self.collect(source: source, config: config)
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(intervalSec))
            } while !Task.isCancelled
        }
        jobTasks[id] = task
    }

    private func scheduleReminderTask(id: String, text: String, delaySeconds: Int) {
        Task {
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }
            try? self.dataStore.markReminderFired(id: id)
            let event = "{\"type\":\"reminder\",\"id\":\"\(id)\",\"text\":\"\(text.jsonEscaped)\"}"
            self.emitter.emit(event)
            self.log("🔔", "Reminder[\(id)] fired: \"\(text)\"")
        }
    }

    private func collect(source: DataSource, config: String) async {
        switch source {
        case .weather:
            await collectWeather(config: config)
        case .customURL:
            await collectCustomURL(config: config)
        }
    }

    // ─── Weather collection ───────────────────────────────

    private func collectWeather(config: String) async {
        guard let cfg = parseConfig(config),
              let city = cfg["city"], !city.isEmpty else {
            log("❌", "Weather job: missing 'city' in config: \(config)")
            return
        }

        do {
            let payload = try await fetchWeather(city: city)
            try dataStore.insertCollectedData(source: DataSource.weather.rawValue, payload: payload)
            let preview = String(payload.prefix(80))
            log("✅", "Job[weather] saved for \(city): \(preview)…")
            // Отправляем полные данные погоды клиенту через SSE
            emitter.emit(payload)
        } catch {
            log("❌", "Weather fetch failed for \(city): \(error)")
        }
    }

    private func fetchWeather(city: String) async throws -> String {
        guard let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=ru&format=json")
        else { throw URLError(.badURL) }

        let (geoData, _) = try await URLSession.shared.data(from: geoURL)
        let geoResp = try JSONDecoder().decode(GeoResponse.self, from: geoData)
        guard let geo = geoResp.results?.first else {
            throw URLError(.cannotFindHost)
        }

        let wURLStr = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(geo.latitude)&longitude=\(geo.longitude)"
            + "&current=temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation,weather_code"
            + "&wind_speed_unit=ms&timezone=auto"
        guard let wURL = URL(string: wURLStr) else { throw URLError(.badURL) }
        let (wData, _) = try await URLSession.shared.data(from: wURL)
        let wResp = try JSONDecoder().decode(WeatherResp.self, from: wData)
        let cur = wResp.current

        let parts = [geo.name, geo.admin1 ?? "", geo.country ?? ""].filter { !$0.isEmpty }
        let place = parts.joined(separator: ", ")

        let payload: [String: Any] = [
            "location":          place,
            "temperature_c":     cur.temperature2m,
            "humidity_percent":  cur.relativeHumidity2m,
            "wind_speed_ms":     cur.windSpeed10m,
            "precipitation_mm":  cur.precipitation,
            "weather_code":      cur.weatherCode
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }

    // ─── Custom URL collection ────────────────────────────

    private func collectCustomURL(config: String) async {
        guard let cfg = parseConfig(config),
              let urlStr = cfg["url"],
              let url = URL(string: urlStr) else {
            log("❌", "CustomURL job: missing/invalid 'url' in config: \(config)")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let payload = String(data: data, encoding: .utf8) ?? "{}"
            try dataStore.insertCollectedData(source: DataSource.customURL.rawValue, payload: payload)
            log("✅", "Job[custom_url] saved: \(String(payload.prefix(80)))…")
        } catch {
            log("❌", "CustomURL fetch failed (\(urlStr)): \(error)")
        }
    }

    // ─── Utilities ────────────────────────────────────────

    private func parseConfig(_ config: String) -> [String: String]? {
        guard let data = config.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return nil }
        return obj
    }

    private func log(_ icon: String, _ message: String) {
        let ts = DateFormatter.logFormatter.string(from: Date())
        print("\(icon) [\(ts)] \(message)")
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - Helpers
// ═══════════════════════════════════════════════════════════

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

extension String {
    var jsonEscaped: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
