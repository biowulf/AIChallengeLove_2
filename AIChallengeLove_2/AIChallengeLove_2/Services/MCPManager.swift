//
//  MCPManager.swift
//  AIChallengeLove_2
//

import Foundation
import Observation
import MCP

// ───────────────────────────────────────────────────────────
// MARK: - Data Models
// ───────────────────────────────────────────────────────────

struct MCPServerConfig: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var isEnabled: Bool = true
}

struct MCPToolInfo: Identifiable {
    var id: String { name }
    let name: String
    let description: String?
    /// Схема входных параметров из MCP Tool.inputSchema.
    /// Используется для построения GigaFunction при function calling.
    let inputSchema: Value?

    /// Конвертирует MCP-инструмент в формат функции GigaChat.
    func toGigaFunction() -> GigaFunction? {
        guard let desc = description else { return nil }

        var props: [String: GigaFunctionProperty] = [:]
        var requiredFields: [String] = []

        if case .object(let schema) = inputSchema {
            // Извлекаем properties: { "properties": { "location": { "type": "string", "description": "..." } } }
            if case .object(let properties) = schema["properties"] {
                for (propName, propValue) in properties {
                    if case .object(let propDict) = propValue {
                        let propType: String
                        if case .string(let t) = propDict["type"] { propType = t } else { propType = "string" }
                        let propDesc: String
                        if case .string(let d) = propDict["description"] { propDesc = d } else { propDesc = propName }
                        props[propName] = GigaFunctionProperty(type: propType, description: propDesc)
                    }
                }
            }
            // Извлекаем required: ["location", ...]
            if case .array(let reqArray) = schema["required"] {
                requiredFields = reqArray.compactMap {
                    if case .string(let s) = $0 { return s } else { return nil }
                }
            }
        }

        guard !props.isEmpty else { return nil }

        return GigaFunction(
            name: name,
            description: desc,
            parameters: GigaFunctionParameters(
                properties: props,
                required: requiredFields.isEmpty ? nil : requiredFields
            ),
            fewShotExamples: nil,
            returnParameters: nil
        )
    }
}

// ───────────────────────────────────────────────────────────
// MARK: - MCPManager
// ───────────────────────────────────────────────────────────

@Observable
final class MCPManager {

    private let defaults     = UserDefaults.standard
    private let serversKey   = "mcp.servers"
    private let isEnabledKey = "mcp.isEnabled"

    var isEnabled: Bool = false {
        didSet { defaults.set(isEnabled, forKey: isEnabledKey) }
    }

    var servers: [MCPServerConfig] = [] {
        didSet { saveServers() }
    }

    var toolsByServer:  [UUID: [MCPToolInfo]] = [:]
    var statusByServer: [UUID: String]        = [:]
    var isConnecting: Bool = false

    /// Живые MCP-клиенты (key = serverID).
    /// Хранятся для последующих вызовов callTool без переподключения.
    private var clientsByServer: [UUID: Client] = [:]

    init() {
        isEnabled = defaults.bool(forKey: isEnabledKey)
        servers   = loadServers()
        // Автоподключение при старте приложения, если MCP был включён ранее.
        if isEnabled && servers.contains(where: { $0.isEnabled }) {
            Task { @MainActor in await self.connectAll() }
        }
    }

    // MARK: - Computed

    /// Все инструменты со всех подключённых серверов (плоский список).
    var allTools: [MCPToolInfo] {
        toolsByServer.values.flatMap { $0 }
    }

    // MARK: - Persistence

    private func saveServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        defaults.set(data, forKey: serversKey)
    }

    private func loadServers() -> [MCPServerConfig] {
        guard let data = defaults.data(forKey: serversKey),
              let saved = try? JSONDecoder().decode([MCPServerConfig].self, from: data),
              !saved.isEmpty else {
            return []
        }
        return saved
    }

    // MARK: - Connect All

    func connectAll() async {
        guard isEnabled else { return }
        isConnecting = true
        defer { isConnecting = false }
        for server in servers where server.isEnabled {
            await connect(to: server)
        }
    }

    // MARK: - Connect Single

    func connect(to config: MCPServerConfig) async {
        guard let url = URL(string: config.url) else {
            statusByServer[config.id] = "Неверный URL"
            return
        }
        statusByServer[config.id] = "Подключение..."
        do {
            let transport = HTTPClientTransport(endpoint: url, streaming: true)
            let client    = Client(name: "AIChallengeLove", version: "1.0.0")
            try await client.connect(transport: transport)

            statusByServer[config.id] = "Получение инструментов..."
            let (tools, _) = try await client.listTools()

            toolsByServer[config.id]  = tools.map {
                MCPToolInfo(name: $0.name, description: $0.description, inputSchema: $0.inputSchema)
            }
            // Сохраняем живой клиент для последующих tool calls
            clientsByServer[config.id] = client

            statusByServer[config.id] = "Подключён (\(tools.count) инструментов)"
            print("[MCP] \(config.name): \(tools.count) tools")
            tools.forEach { print("  - \($0.name): \($0.description ?? "")") }
        } catch {
            statusByServer[config.id] = "Ошибка: \(error.localizedDescription)"
            clientsByServer.removeValue(forKey: config.id)
            print("[MCP] Error connecting to \(config.name): \(error)")
        }
    }

    // MARK: - Call Tool

    /// Вызывает MCP-инструмент по имени.
    /// - Parameters:
    ///   - name: Имя инструмента (например "get_weather")
    ///   - jsonArguments: Аргументы в виде JSON-строки, полученной от GigaChat
    ///     (например `"{\"location\":\"Москва\"}"`)
    /// - Returns: Текстовый ответ инструмента
    func callTool(name: String, jsonArguments: String) async throws -> String {
        // Найти сервер, у которого есть этот инструмент
        guard let serverID = toolsByServer.first(where: { pair in
            pair.value.contains(where: { $0.name == name })
        })?.key,
              let client = clientsByServer[serverID] else {
            throw MCPManagerError.toolNotFound(name)
        }

        // Распарсить JSON-строку аргументов → [String: Value]
        var mcpArgs: [String: Value] = [:]
        if let data = jsonArguments.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, val) in dict {
                if let s = val as? String  { mcpArgs[key] = .string(s)   }
                else if let i = val as? Int    { mcpArgs[key] = .int(i)   }
                else if let d = val as? Double { mcpArgs[key] = .double(d) }
            }
        }

        let (content, _) = try await client.callTool(
            name: name,
            arguments: mcpArgs.isEmpty ? nil : mcpArgs
        )

        // Собрать текст из ответа
        let text = content.compactMap { item -> String? in
            if case .text(let t) = item { return t }
            return nil
        }.joined(separator: "\n")

        print("[MCP] Tool '\(name)' result: \(text.prefix(200))")
        return text
    }

    // MARK: - Server Management

    func addServer(name: String, url: String) {
        servers.append(MCPServerConfig(name: name, url: url))
    }

    func removeServer(id: UUID) {
        servers.removeAll { $0.id == id }
        toolsByServer.removeValue(forKey: id)
        statusByServer.removeValue(forKey: id)
        clientsByServer.removeValue(forKey: id)
    }

    func tools(for id: UUID) -> [MCPToolInfo] {
        toolsByServer[id] ?? []
    }

    func status(for id: UUID) -> String? {
        statusByServer[id]
    }
}

// MARK: - Errors

enum MCPManagerError: LocalizedError {
    case toolNotFound(String)
    case clientNotConnected(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "MCP tool '\(name)' not found on any connected server"
        case .clientNotConnected(let name):
            return "No active MCP client for tool '\(name)'"
        }
    }
}
