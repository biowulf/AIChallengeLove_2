import Vapor
import Foundation

// ═══════════════════════════════════════════════════════════
// MARK: - RequestLoggingMiddleware
// ═══════════════════════════════════════════════════════════

/// Logs every POST /mcp request and response to stdout.
///
/// Console format:
///
///     → [12:34:01] POST /mcp
///       {"jsonrpc":"2.0","method":"tools/call","params":{...}}
///
///     ← [12:34:01] 200 OK  (8ms)
///       {"jsonrpc":"2.0","result":{...}}
///
struct RequestLoggingMiddleware: AsyncMiddleware {

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let start = Date()
        let path  = request.url.path

        // Log request body only for /mcp endpoint
        if path == "/mcp" {
            let bodyStr = request.body.string.map { prettyJSON($0) } ?? "<empty>"
            logLine("→", "\(request.method) \(path)")
            logBody(bodyStr)
        }

        let response = try await next.respond(to: request)

        if path == "/mcp" {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let status  = "\(response.status.code) \(response.status.reasonPhrase)"
            logLine("←", "\(status)  (\(elapsed)ms)")

            if let bodyData = response.body.data {
                let bodyStr = String(data: bodyData, encoding: .utf8) ?? "<binary>"
                logBody(prettyJSON(bodyStr))
            }
            print("")  // blank separator between request/response pairs
        }

        return response
    }

    // ─── Helpers ──────────────────────────────────────────

    private func logLine(_ arrow: String, _ message: String) {
        let ts = timeString()
        print("\(arrow) [\(ts)] \(message)")
    }

    private func logBody(_ body: String) {
        // Indent each line by 2 spaces, truncate if very long
        let lines = body.components(separatedBy: "\n")
        let truncated = lines.prefix(30).joined(separator: "\n")
        let suffix = lines.count > 30 ? "\n  … (\(lines.count - 30) more lines)" : ""
        print(truncated.components(separatedBy: "\n")
            .map { "  \($0)" }
            .joined(separator: "\n") + suffix)
    }

    private func prettyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
              let str  = String(data: pretty, encoding: .utf8)
        else { return raw }
        return str
    }

    private func timeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
