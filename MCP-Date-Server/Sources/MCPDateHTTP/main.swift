import Foundation
import MCP
import Vapor

typealias VaporResponse = Vapor.Response
typealias MCPServer     = MCP.Server

// ═══════════════════════════════════════════════════════════
// MARK: - Tool Definition
// ═══════════════════════════════════════════════════════════

private let getCurrentDateTool = Tool(
    name: "get_current_date",
    description: "Возвращает сегодняшнюю дату и день недели. Вызывай первым когда пользователь упоминает относительные даты: «завтра», «в субботу», «на выходных», «на следующей неделе» — ты не знаешь текущую дату и не можешь вычислить её без этого инструмента.",
    inputSchema: .object([
        "type":       .string("object"),
        "properties": .object([:]),
        "required":   .array([])
    ])
)

// ═══════════════════════════════════════════════════════════
// MARK: - Tool Handler
// ═══════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════
// MARK: - Session ID Generator
// ═══════════════════════════════════════════════════════════

private struct FixedSessionIDGenerator: SessionIDGenerator {
    let sessionID: String
    func generateSessionID() -> String { sessionID }
}

// ═══════════════════════════════════════════════════════════
// MARK: - MCP Session Manager
// ═══════════════════════════════════════════════════════════

actor MCPSessionManager {

    struct SessionContext {
        let server:    MCPServer
        let transport: StatefulHTTPServerTransport
        let createdAt: Date
        var lastAccessedAt: Date
    }

    private var sessions: [String: SessionContext] = [:]

    func handleRequest(_ req: Vapor.Request) async -> VaporResponse {
        let httpReq   = makeHTTPRequest(from: req)
        let sessionID = httpReq.header(HTTPHeaderName.sessionID)

        if let sessionID, var ctx = sessions[sessionID] {
            ctx.lastAccessedAt = Date()
            sessions[sessionID] = ctx

            let httpResp = await ctx.transport.handleRequest(httpReq)

            if httpReq.method.uppercased() == "DELETE" && httpResp.statusCode == 200 {
                await terminateSession(sessionID)
            }
            return vaporResponse(from: httpResp)
        }

        if httpReq.method.uppercased() == "POST",
           let body = httpReq.body,
           isInitializeRequest(body)
        {
            return await createSessionAndHandle(httpReq)
        }

        if sessionID != nil {
            return makeErrorResponse(status: .notFound,
                                     message: "Not Found: Session not found or expired")
        }
        return makeErrorResponse(status: .badRequest,
                                 message: "Bad Request: Missing Mcp-Session-Id header")
    }

    private func createSessionAndHandle(_ request: HTTPRequest) async -> VaporResponse {
        let sessionID = UUID().uuidString

        let pipeline = StandardValidationPipeline(validators: [
            OriginValidator.disabled,
            AcceptHeaderValidator(mode: .sseRequired),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
            SessionValidator(),
        ])

        let transport = StatefulHTTPServerTransport(
            sessionIDGenerator: FixedSessionIDGenerator(sessionID: sessionID),
            validationPipeline: pipeline
        )

        let server = MCPServer(
            name: "swift-mcp-date",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [getCurrentDateTool])
        }

        await server.withMethodHandler(CallTool.self) { params in
            guard params.name == "get_current_date" else {
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }
            return handleGetCurrentDate()
        }

        do {
            try await server.start(transport: transport)
        } catch {
            return makeErrorResponse(status: .internalServerError,
                                     message: "Failed to start MCP server: \(error)")
        }

        sessions[sessionID] = SessionContext(
            server:          server,
            transport:       transport,
            createdAt:       Date(),
            lastAccessedAt:  Date()
        )

        print("✅ MCP-Date session \(sessionID.prefix(8))… created")

        let httpResp = await transport.handleRequest(request)

        if case .error = httpResp {
            await terminateSession(sessionID)
        }

        return vaporResponse(from: httpResp)
    }

    private func terminateSession(_ sessionID: String) async {
        guard let ctx = sessions.removeValue(forKey: sessionID) else { return }
        await ctx.transport.disconnect()
        print("🔌 MCP-Date session \(sessionID.prefix(8))… terminated")
    }

    func startCleanupLoop(timeout: TimeInterval = 3600) {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(60))
                let now     = Date()
                let expired = sessions.filter { _, ctx in
                    now.timeIntervalSince(ctx.lastAccessedAt) > timeout
                }
                for (id, _) in expired {
                    print("⏰ MCP-Date session \(id.prefix(8))… idle timeout, removing")
                    await terminateSession(id)
                }
            }
        }
    }

    var sessionCount: Int { sessions.count }
}

// ═══════════════════════════════════════════════════════════
// MARK: - Helpers
// ═══════════════════════════════════════════════════════════

private func isInitializeRequest(_ data: Data) -> Bool {
    guard let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let method = json["method"] as? String
    else { return false }
    return method == "initialize"
}

private func makeHTTPRequest(from req: Vapor.Request) -> HTTPRequest {
    var headers: [String: String] = [:]
    for (name, value) in req.headers { headers[name] = value }
    let body = req.body.data.map { Data(buffer: $0) }
    return HTTPRequest(method: req.method.rawValue, headers: headers, body: body)
}

private func vaporResponse(from httpResp: HTTPResponse) -> VaporResponse {
    var vaporHeaders = HTTPHeaders()
    for (key, value) in httpResp.headers {
        vaporHeaders.replaceOrAdd(name: key, value: value)
    }

    switch httpResp {
    case .stream(let sseStream, _):
        let response = VaporResponse(
            status: .init(statusCode: httpResp.statusCode),
            headers: vaporHeaders
        )
        response.body = .init(stream: { writer in
            Task {
                do {
                    for try await chunk in sseStream {
                        // Логируем SSE-событие (пропускаем пустые keep-alive пакеты)
                        if let raw = String(data: chunk, encoding: .utf8) {
                            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && trimmed != ":" {
                                print("← SSE: \(trimmed.prefix(800))")
                            }
                        }
                        _ = writer.write(.buffer(ByteBuffer(bytes: chunk)))
                    }
                } catch { }
                _ = writer.write(.end)
            }
        })
        return response

    default:
        return VaporResponse(
            status: .init(statusCode: httpResp.statusCode),
            headers: vaporHeaders,
            body: httpResp.bodyData.map { .init(data: $0) } ?? .empty
        )
    }
}

private func makeErrorResponse(status: HTTPResponseStatus, message: String) -> VaporResponse {
    let body = try? JSONSerialization.data(withJSONObject: [
        "jsonrpc": "2.0",
        "error":   ["code": -32600, "message": message] as [String: Any],
        "id":      NSNull()
    ] as [String: Any])
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/json")
    return VaporResponse(status: status, headers: headers,
                         body: body.map { .init(data: $0) } ?? .empty)
}

// ═══════════════════════════════════════════════════════════
// MARK: - Entry Point
// ═══════════════════════════════════════════════════════════

let sessionManager = MCPSessionManager()
await sessionManager.startCleanupLoop()

let env = try Environment.detect()
let app = try await Application.make(env)

app.http.server.configuration.hostname = "0.0.0.0"
app.http.server.configuration.port     = 8081

app.middleware.use(
    CORSMiddleware(configuration: .init(
        allowedOrigin:  .all,
        allowedMethods: [.GET, .POST, .DELETE, .OPTIONS],
        allowedHeaders: [
            .accept, .authorization, .contentType, .origin,
            .init("Mcp-Session-Id"),
            .init("Mcp-Protocol-Version"),
            .init("Last-Event-Id"),
        ]
    )),
    at: .beginning
)
app.middleware.use(RequestLoggingMiddleware(), at: .beginning)

app.get("health") { _ -> [String: String] in
    let n = await sessionManager.sessionCount
    return ["status": "ok", "server": "swift-mcp-date", "mcp_sessions": "\(n)"]
}

app.get { _ in
    ["name": "swift-mcp-date", "version": "1.0.0",
     "transport": "MCP Streamable HTTP — POST/GET/DELETE /mcp"]
}

app.on(.POST, "mcp", body: .collect(maxSize: "1mb")) { req async -> VaporResponse in
    await sessionManager.handleRequest(req)
}
app.get("mcp") { req async -> VaporResponse in
    await sessionManager.handleRequest(req)
}
app.on(.DELETE, "mcp") { req async -> VaporResponse in
    await sessionManager.handleRequest(req)
}
app.on(.OPTIONS, "mcp") { _ -> VaporResponse in
    VaporResponse(status: .noContent)
}

print("""

📅 MCP Date Server запущен!
────────────────────────────────────────────────────
  POST   http://localhost:8081/mcp
  GET    http://localhost:8081/mcp
  DELETE http://localhost:8081/mcp

Инструменты:
  • get_current_date — актуальная дата + день недели (ru)

GET  http://localhost:8081/health — Health check
────────────────────────────────────────────────────

""")

try await app.execute()
try await app.asyncShutdown()
