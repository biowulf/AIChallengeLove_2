import Foundation
import MCP

@main
struct MCPGitClientApp {
    static func main() async throws {
        let serverURL = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "http://localhost:8080/mcp"

        print("🔌 Подключение к \(serverURL)...")

        let client = Client(name: "mcp-git-client", version: "1.0.0")
        let transport = HTTPClientTransport(
            endpoint: URL(string: serverURL)!,
            streaming: false
        )

        let initResult = try await client.connect(transport: transport)
        print("✅ Подключено: \(initResult.serverInfo.name) v\(initResult.serverInfo.version)")

        // Список инструментов
        let (tools, _) = try await client.listTools()
        print("\n🔧 Инструменты (\(tools.count)):")
        for tool in tools {
            print("   • \(tool.name) — \(tool.description ?? "")")
        }

        // list_repos
        print("\n📦 Swift-репозитории:")
        let (reposContent, _) = try await client.callTool(
            name: "list_repos",
            arguments: ["language": .string("Swift")]
        )
        for item in reposContent {
            if case .text(let text) = item { print(text) }
        }

        // get_issues
        print("\n🐛 Открытые issues (ios-weather-app):")
        let (issuesContent, _) = try await client.callTool(
            name: "get_issues",
            arguments: ["repo": .string("ios-weather-app"), "state": .string("open")]
        )
        for item in issuesContent {
            if case .text(let text) = item { print(text) }
        }

        // get_commits
        print("\n📝 Последние коммиты:")
        let (commitsContent, _) = try await client.callTool(
            name: "get_commits",
            arguments: ["repo": .string("ios-weather-app"), "limit": .int(3)]
        )
        for item in commitsContent {
            if case .text(let text) = item { print(text) }
        }

        // create_issue
        print("\n✨ Создание issue:")
        let (createContent, _) = try await client.callTool(
            name: "create_issue",
            arguments: [
                "repo": .string("ios-weather-app"),
                "title": .string("Add WidgetKit support"),
                "body": .string("Need iOS 19 WidgetKit integration")
            ]
        )
        for item in createContent {
            if case .text(let text) = item { print(text) }
        }

        print("\n🏁 Готово!")
    }
}