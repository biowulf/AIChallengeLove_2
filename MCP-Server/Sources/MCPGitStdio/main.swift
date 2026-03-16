import Foundation
import MCP
import GitTools

@main
struct MCPGitStdioApp {
    static func main() async throws {
        let server = createMCPServer()
        await registerToolHandlers(on: server)

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}