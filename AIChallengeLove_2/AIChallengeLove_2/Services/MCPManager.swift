//
//  MCPManager.swift
//  AIChallengeLove_2
//

import Foundation
import Observation
import MCP

// MARK: - Data Models

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
}

// MARK: - MCPManager

@Observable
final class MCPManager {

    private let defaults = UserDefaults.standard
    private let serversKey = "mcp.servers"
    private let isEnabledKey = "mcp.isEnabled"

    var isEnabled: Bool = false {
        didSet { defaults.set(isEnabled, forKey: isEnabledKey) }
    }

    var servers: [MCPServerConfig] = [] {
        didSet { saveServers() }
    }

    var toolsByServer: [UUID: [MCPToolInfo]] = [:]
    var statusByServer: [UUID: String] = [:]
    var isConnecting: Bool = false

    init() {
        isEnabled = defaults.bool(forKey: isEnabledKey)
        servers = loadServers()
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
            let client = Client(name: "AIChallengeLove", version: "1.0.0")
            try await client.connect(transport: transport)
            statusByServer[config.id] = "Получение инструментов..."
            let (tools, _) = try await client.listTools()
            toolsByServer[config.id] = tools.map {
                MCPToolInfo(name: $0.name, description: $0.description)
            }
            statusByServer[config.id] = "Подключён (\(tools.count) инструментов)"
            print("[MCP] \(config.name): \(tools.count) tools")
            tools.forEach { print("  - \($0.name): \($0.description ?? "")") }
        } catch {
            statusByServer[config.id] = "Ошибка: \(error.localizedDescription)"
            print("[MCP] Error connecting to \(config.name): \(error)")
        }
    }

    // MARK: - Server Management

    func addServer(name: String, url: String) {
        let config = MCPServerConfig(name: name, url: url)
        servers.append(config) // didSet → saveServers()
    }

    func removeServer(id: UUID) {
        servers.removeAll { $0.id == id } // didSet → saveServers()
        toolsByServer.removeValue(forKey: id)
        statusByServer.removeValue(forKey: id)
    }

    func tools(for id: UUID) -> [MCPToolInfo] {
        toolsByServer[id] ?? []
    }

    func status(for id: UUID) -> String? {
        statusByServer[id]
    }
}
