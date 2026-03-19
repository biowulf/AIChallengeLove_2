import Foundation
import MCP
import Vapor
import GitTools
import SchedulerTools

typealias VaporResponse = Vapor.Response
typealias MCPServer     = MCP.Server       // disambiguate from Vapor.Server

// ═══════════════════════════════════════════════════════════
// MARK: - Singletons (live for the entire server lifetime)
// ═══════════════════════════════════════════════════════════

let dbPath: String = {
    let dir = FileManager.default.currentDirectoryPath
    return "\(dir)/mcp_data.sqlite"
}()

let dataStore: DataStore = {
    do {
        return try DataStore(path: dbPath)
    } catch {
        fatalError("❌ Cannot open SQLite at \(dbPath): \(error)")
    }
}()

let eventEmitter = EventEmitter()
let scheduler    = SchedulerService(dataStore: dataStore, emitter: eventEmitter)

// Restore only reminders on startup.
// Periodic jobs are NOT auto-started — they start only when
// schedule_job is explicitly called via MCP tool.
await scheduler.restoreReminders()

// ═══════════════════════════════════════════════════════════
// MARK: - Session ID Generator (SDK protocol conformance)
// ═══════════════════════════════════════════════════════════

/// Generates a pre-determined session ID so the HTTP layer can embed
/// it in the response header before `transport.handleRequest` runs.
private struct FixedSessionIDGenerator: SessionIDGenerator {
    let sessionID: String
    func generateSessionID() -> String { sessionID }
}

// ═══════════════════════════════════════════════════════════
// MARK: - MCP Session Manager
// ═══════════════════════════════════════════════════════════
// Owns all stateful MCP sessions. Each session has:
//   • one Server    — handles tool call logic
//   • one Transport — StatefulHTTPServerTransport (POST+GET+DELETE /mcp)
//   • one push Task — forwards EventEmitter events to the GET /mcp SSE stream

actor MCPSessionManager {

    struct SessionContext {
        let server:    MCPServer
        let transport: StatefulHTTPServerTransport
        let pushTask:  Task<Void, Never>
        let createdAt: Date
        var lastAccessedAt: Date
    }

    private var sessions: [String: SessionContext] = [:]

    // ─── Main entry: route an incoming Vapor request ────────

    func handleRequest(_ req: Vapor.Request) async -> VaporResponse {
        let httpReq = makeHTTPRequest(from: req)
        let sessionID = httpReq.header(HTTPHeaderName.sessionID)

        // Route to an existing session
        if let sessionID, var ctx = sessions[sessionID] {
            ctx.lastAccessedAt = Date()
            sessions[sessionID] = ctx

            let httpResp = await ctx.transport.handleRequest(httpReq)

            // Clean up on successful DELETE
            if httpReq.method.uppercased() == "DELETE" && httpResp.statusCode == 200 {
                await terminateSession(sessionID)
            }
            return vaporResponse(from: httpResp)
        }

        // No session — create one only for `initialize` POST requests
        if httpReq.method.uppercased() == "POST",
           let body = httpReq.body,
           isInitializeRequest(body)
        {
            return await createSessionAndHandle(httpReq)
        }

        // No session and not an initialize request
        if sessionID != nil {
            return makeErrorResponse(status: .notFound,
                                     message: "Not Found: Session not found or expired")
        }
        return makeErrorResponse(status: .badRequest,
                                 message: "Bad Request: Missing \(HTTPHeaderName.sessionID) header")
    }

    // ─── Session creation ───────────────────────────────────

    private func createSessionAndHandle(_ request: HTTPRequest) async -> VaporResponse {
        let sessionID = UUID().uuidString

        // Permissive validation pipeline suitable for mobile/local clients:
        // origin check disabled, SSE Accept required (HTTPClientTransport sends it),
        // Content-Type + protocol version + session ID validated as usual.
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

        // Register tool handlers on a fresh MCP Server instance
        let server = MCPServer(
            name: "swift-mcp-scheduler",
            version: "2.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: WeatherToolDefs.all + SchedulerToolDefs.all)
        }

        await server.withMethodHandler(CallTool.self) { params in
            if params.name == "get_weather" {
                return try await handleToolCall(name: params.name, arguments: params.arguments)
            }
            return try await handleSchedulerToolCall(
                name: params.name,
                arguments: params.arguments,
                scheduler: scheduler,
                dataStore: dataStore
            )
        }

        do {
            try await server.start(transport: transport)
        } catch {
            return makeErrorResponse(status: .internalServerError,
                                     message: "Failed to start MCP server: \(error)")
        }

        // Subscribe to EventEmitter and forward push events to the GET /mcp SSE stream.
        // Events arrive as JSON strings → wrap in a standard MCP notifications/message.
        let pushTask = Task { [transport] in
            let (subscriptionID, pushStream) = eventEmitter.subscribe()
            defer { eventEmitter.unsubscribe(subscriptionID) }

            for await event in pushStream {
                let notif: [String: Any] = [
                    "jsonrpc": "2.0",
                    "method":  "notifications/message",
                    "params":  ["level": "info", "data": event, "logger": "mcp-scheduler"] as [String: Any]
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: notif) else { continue }
                try? await transport.send(data)
            }
        }

        // Store the session BEFORE calling handleRequest so that parallel
        // requests (e.g. GET /mcp) can find it if they arrive during the await.
        sessions[sessionID] = SessionContext(
            server:          server,
            transport:       transport,
            pushTask:        pushTask,
            createdAt:       Date(),
            lastAccessedAt:  Date()
        )

        print("✅ MCP session \(sessionID.prefix(8))… created")

        let httpResp = await transport.handleRequest(request)

        // If the transport immediately returned an error (shouldn't happen for init,
        // but guard anyway), clean up.
        if case .error = httpResp {
            await terminateSession(sessionID)
        }

        return vaporResponse(from: httpResp)
    }

    // ─── Session teardown ───────────────────────────────────

    private func terminateSession(_ sessionID: String) async {
        guard let ctx = sessions.removeValue(forKey: sessionID) else { return }
        ctx.pushTask.cancel()
        await ctx.transport.disconnect()
        print("🔌 MCP session \(sessionID.prefix(8))… terminated")
    }

    // ─── Periodic cleanup of idle sessions ─────────────────

    func startCleanupLoop(timeout: TimeInterval = 3600) {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(60))
                let now = Date()
                let expired = sessions.filter { _, ctx in
                    now.timeIntervalSince(ctx.lastAccessedAt) > timeout
                }
                for (id, _) in expired {
                    print("⏰ MCP session \(id.prefix(8))… idle timeout, removing")
                    await terminateSession(id)
                }
            }
        }
    }

    var sessionCount: Int { sessions.count }
}

// ═══════════════════════════════════════════════════════════
// MARK: - JSON-RPC Helpers
// ═══════════════════════════════════════════════════════════

/// Returns true when the JSON body is an MCP `initialize` request.
/// `JSONRPCMessageKind` from the SDK is package-internal, so we parse manually.
private func isInitializeRequest(_ data: Data) -> Bool {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let method = json["method"] as? String
    else { return false }
    return method == "initialize"
}

// ═══════════════════════════════════════════════════════════
// MARK: - Vapor ↔ SDK Bridging Helpers
// ═══════════════════════════════════════════════════════════

/// Convert Vapor's request into the SDK's framework-agnostic HTTPRequest.
private func makeHTTPRequest(from req: Vapor.Request) -> HTTPRequest {
    var headers: [String: String] = [:]
    for (name, value) in req.headers { headers[name] = value }
    let body = req.body.data.map { Data(buffer: $0) }
    return HTTPRequest(method: req.method.rawValue, headers: headers, body: body)
}

/// Convert the SDK's HTTPResponse into a Vapor Response.
/// SSE streaming responses are wired to Vapor's streaming body.
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
                        _ = writer.write(.buffer(ByteBuffer(bytes: chunk)))
                    }
                } catch {
                    // Stream ended (client disconnected or transport closed)
                }
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

/// Build a plain JSON error response for routing-level failures.
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
app.http.server.configuration.port     = 8080

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

// ── Health check ──────────────────────────────────────────
app.get("health") { _ -> [String: String] in
    let n = await sessionManager.sessionCount
    return ["status": "ok", "server": "swift-mcp-scheduler",
            "db": dbPath, "mcp_sessions": "\(n)"]
}

// ── Root info ─────────────────────────────────────────────
app.get { _ in
    [
        "name":      "swift-mcp-scheduler",
        "version":   "2.0.0",
        "transport": "MCP Streamable HTTP — POST/GET/DELETE /mcp",
        "push":      "GET /mcp keeps SSE open for server-initiated events"
    ]
}

// ══════════════════════════════════════════════════════════
// MARK: - MCP Streamable HTTP Transport  (POST / GET / DELETE /mcp)
// ══════════════════════════════════════════════════════════
//
//  Implements MCP Streamable HTTP spec (2025):
//
//  POST /mcp   — JSON-RPC request; response arrives as SSE stream on same connection
//  GET  /mcp   — standalone SSE stream for server-initiated push notifications
//  DELETE /mcp — terminate session
//
//  All requests carry `Mcp-Session-Id` header after initialization.
//  On first POST (initialize), a new session is created and the header is
//  returned in the response.
// ══════════════════════════════════════════════════════════

app.on(.POST, "mcp", body: .collect(maxSize: "10mb")) { req async -> VaporResponse in
    await sessionManager.handleRequest(req)
}

app.get("mcp") { req async -> VaporResponse in
    await sessionManager.handleRequest(req)
}

app.on(.DELETE, "mcp") { req async -> VaporResponse in
    await sessionManager.handleRequest(req)
}

// OPTIONS for CORS preflight
app.on(.OPTIONS, "mcp") { _ -> VaporResponse in
    VaporResponse(status: .noContent)
}

print("""

🚀 MCP Scheduler Server запущен!
────────────────────────────────────────────────────
Transport — MCP Streamable HTTP (swift-sdk StatefulHTTPServerTransport):

  POST   http://localhost:8080/mcp  ← JSON-RPC запрос (ответ через SSE)
  GET    http://localhost:8080/mcp  ← SSE-поток push-событий (reminders и т.д.)
  DELETE http://localhost:8080/mcp  ← завершить сессию

Клиент: HTTPClientTransport(endpoint: .../mcp, streaming: true)

GET  http://localhost:8080/health — Health check
────────────────────────────────────────────────────
Инструменты:
  • get_weather     — текущая погода по городу
  • remind_weather  — напоминание о погоде (каждые N минут или один раз через N минут)
  • stop_weather    — отменить напоминание

База данных: \(dbPath)
────────────────────────────────────────────────────

""")

try await app.execute()
try await app.asyncShutdown()
