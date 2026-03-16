import Foundation
import MCP
import Vapor
import GitTools

typealias VaporResponse = Vapor.Response

@main
struct MCPGitHTTPApp {
    static func main() async throws {
        let env = try Environment.detect()
        let app = try await Application.make(env)

        app.http.server.configuration.hostname = "0.0.0.0"
        app.http.server.configuration.port = 8080

        app.middleware.use(
            CORSMiddleware(configuration: .init(
                allowedOrigin: .all,
                allowedMethods: [.GET, .POST, .OPTIONS],
                allowedHeaders: [.accept, .authorization, .contentType, .origin]
            )),
            at: .beginning
        )

        // ── Health check ──────────────────────────────────────
        app.get("health") { _ in ["status": "ok", "server": "swift-git-mcp"] }

        // ── GET /mcp → 405 ────────────────────────────────────
        // iOS-клиент с streaming=true отправляет GET после initialize,
        // ждёт именно 405 чтобы штатно отменить SSE-таск.
        // Без этого Vapor вернёт 404 и клиент будет ретраить вечно.
        app.get("mcp") { _ -> VaporResponse in
            var h = HTTPHeaders()
            h.add(name: "Allow", value: "POST")
            return VaporResponse(status: .methodNotAllowed, headers: h, body: .empty)
        }

        // ── POST /mcp — MCP JSON-RPC ──────────────────────────
        //
        // Архитектура: НОВЫЙ Server+Transport на каждый HTTP-запрос.
        //
        // Почему не один shared Server:
        //   Server.isInitialized = true после первого initialize и навсегда
        //   блокирует повторные подключения (reconnect, несколько клиентов).
        //
        // Почему работает с per-request:
        //   Server создаётся с strict: false (дефолт).
        //   В non-strict режиме tools/list и tools/call не проверяют
        //   isInitialized → каждый запрос обрабатывается независимо.
        //
        // Как избежать утечки: вызываем transport.disconnect() после
        //   handleRequest(), что завершает стрим и останавливает фоновый Task.
        app.post("mcp") { req async throws -> VaporResponse in
            guard let bodyBuffer = req.body.data else {
                throw Abort(.badRequest, reason: "Empty body")
            }
            let bodyData = Data(buffer: bodyBuffer)

            // Пробрасываем ВСЕ заголовки реального запроса в SDK-тип.
            // Без этого AcceptHeaderValidator видит пустой Accept и возвращает 406.
            var headers: [String: String] = [:]
            for (name, value) in req.headers { headers[name] = value }

            let httpRequest = HTTPRequest(method: "POST", headers: headers, body: bodyData)

            // Создаём сервер и транспорт — без OriginValidator (блокирует iOS-девайс)
            let server = createMCPServer()
            await registerToolHandlers(on: server)
            let transport = StatelessHTTPServerTransport(
                validationPipeline: StandardValidationPipeline(validators: [
                    OriginValidator.disabled,
                    AcceptHeaderValidator(mode: .jsonOnly),
                    ContentTypeValidator(),
                    ProtocolVersionValidator(),
                ])
            )
            try await server.start(transport: transport)

            let httpResponse = await transport.handleRequest(httpRequest)

            // Завершаем стрим → фоновый Task Server'а получает .finished и выходит
            await transport.disconnect()

            // Конвертируем ответ SDK → Vapor
            var vaporHeaders = HTTPHeaders()
            for (key, value) in httpResponse.headers {
                vaporHeaders.add(name: key, value: value)
            }
            if vaporHeaders["Content-Type"].isEmpty {
                vaporHeaders.add(name: "Content-Type", value: "application/json")
            }

            return VaporResponse(
                status: .init(statusCode: httpResponse.statusCode),
                headers: vaporHeaders,
                body: .init(data: httpResponse.bodyData ?? Data())
            )
        }

        app.get { _ in ["name": "swift-weather-mcp", "version": "1.0.0", "endpoint": "POST /mcp"] }

        print("""

        🚀 MCP Weather Server (Vapor) запущен!
        ────────────────────────────────────────
        POST http://localhost:8080/mcp    — MCP JSON-RPC
        GET  http://localhost:8080/health — Health check
        Инструмент: get_weather (Open-Meteo API)
        ────────────────────────────────────────

        """)

        try await app.execute()
        try await app.asyncShutdown()
    }
}
