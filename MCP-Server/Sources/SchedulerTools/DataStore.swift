import Foundation
import SQLite3

// ═══════════════════════════════════════════════════════════
// MARK: - Error
// ═══════════════════════════════════════════════════════════

public enum DataStoreError: Error {
    case cannotOpen(String)
    case prepareFailed(String)
    case stepFailed(Int32)
}

// ═══════════════════════════════════════════════════════════
// MARK: - DataStore
// ═══════════════════════════════════════════════════════════

/// Thread-safe SQLite wrapper.
/// All public methods acquire `lock` before touching the database.
public final class DataStore: @unchecked Sendable {

    private var db: OpaquePointer?
    private let lock = NSLock()

    // SQLITE_TRANSIENT: SQLite copies the string before the call returns
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DataStoreError.cannotOpen(msg)
        }
        try createTables()
    }

    deinit { sqlite3_close(db) }

    // ─── Schema ──────────────────────────────────────────

    private func createTables() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS collected_data (
                id        TEXT PRIMARY KEY,
                source    TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                payload   TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS scheduled_jobs (
                id           TEXT PRIMARY KEY,
                source       TEXT NOT NULL,
                interval_sec INTEGER NOT NULL,
                config       TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS reminders (
                id      TEXT PRIMARY KEY,
                text    TEXT NOT NULL,
                fire_at INTEGER NOT NULL,
                fired   INTEGER NOT NULL DEFAULT 0
            );
            """
        lock.lock(); defer { lock.unlock() }
        var errmsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errmsg)
        if rc != SQLITE_OK {
            let msg = errmsg.map { String(cString: $0) } ?? "exec error"
            sqlite3_free(errmsg)
            throw DataStoreError.prepareFailed(msg)
        }
    }

    // ─── Collected Data ───────────────────────────────────

    public func insertCollectedData(source: String, payload: String) throws {
        let id = UUID().uuidString
        let ts = Int64(Date().timeIntervalSince1970)
        lock.lock(); defer { lock.unlock() }
        let sql = "INSERT INTO collected_data (id, source, timestamp, payload) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, source, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, ts)
        sqlite3_bind_text(stmt, 4, payload, -1, SQLITE_TRANSIENT)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else { throw DataStoreError.stepFailed(rc) }
    }

    public func queryCollectedData(source: String, since: Date) throws -> [DataRecord] {
        let sinceTs = Int64(since.timeIntervalSince1970)
        lock.lock(); defer { lock.unlock() }
        let sql = "SELECT id, source, timestamp, payload FROM collected_data WHERE source = ? AND timestamp >= ? ORDER BY timestamp ASC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, source, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, sinceTs)
        var records: [DataRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id      = columnText(stmt, 0)
            let src     = columnText(stmt, 1)
            let ts      = Double(sqlite3_column_int64(stmt, 2))
            let payload = columnText(stmt, 3)
            records.append(DataRecord(id: id, source: src,
                                      timestamp: Date(timeIntervalSince1970: ts),
                                      payload: payload))
        }
        return records
    }

    // ─── Scheduled Jobs ───────────────────────────────────

    public func upsertScheduledJob(id: String, source: String, intervalSec: Int, config: String) throws {
        lock.lock(); defer { lock.unlock() }
        let sql = "INSERT OR REPLACE INTO scheduled_jobs (id, source, interval_sec, config) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, source, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, Int64(intervalSec))
        sqlite3_bind_text(stmt, 4, config, -1, SQLITE_TRANSIENT)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else { throw DataStoreError.stepFailed(rc) }
    }

    public func deleteScheduledJob(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM scheduled_jobs WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    public func loadScheduledJobs() throws -> [ScheduledJob] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, source, interval_sec, config FROM scheduled_jobs", -1, &stmt, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        var jobs: [ScheduledJob] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id          = columnText(stmt, 0)
            let sourceStr   = columnText(stmt, 1)
            let intervalSec = Int(sqlite3_column_int64(stmt, 2))
            let config      = columnText(stmt, 3)
            let source      = DataSource(rawValue: sourceStr) ?? .weather
            jobs.append(ScheduledJob(id: id, source: source, intervalSec: intervalSec, config: config))
        }
        return jobs
    }

    // ─── Reminders ────────────────────────────────────────

    public func insertReminder(id: String, text: String, fireAt: Date) throws {
        let ts = Int64(fireAt.timeIntervalSince1970)
        lock.lock(); defer { lock.unlock() }
        let sql = "INSERT OR IGNORE INTO reminders (id, text, fire_at, fired) VALUES (?, ?, ?, 0)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, ts)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE else { throw DataStoreError.stepFailed(rc) }
    }

    public func markReminderFired(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE reminders SET fired = 1 WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    public func deleteReminders(
        id: String? = nil,
        textContains: String? = nil,
        all: Bool = false
    ) throws -> (count: Int, deleted: [(id: String, text: String)]) {
        lock.lock(); defer { lock.unlock() }

        // Build SELECT to find what we'll delete
        let selectSQL: String
        var boundParam: String? = nil
        if all {
            selectSQL = "SELECT id, text FROM reminders"
        } else if let specificID = id {
            selectSQL = "SELECT id, text FROM reminders WHERE id = ?"
            boundParam = specificID
        } else if let needle = textContains {
            selectSQL = "SELECT id, text FROM reminders WHERE lower(text) LIKE lower(?)"
            boundParam = "%\(needle)%"
        } else {
            return (0, [])
        }

        // Fetch rows to delete
        var toDelete: [(id: String, text: String)] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK {
            if let p = boundParam {
                sqlite3_bind_text(stmt, 1, p, -1, SQLITE_TRANSIENT)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                toDelete.append((id: columnText(stmt, 0), text: columnText(stmt, 1)))
            }
        }
        sqlite3_finalize(stmt)

        guard !toDelete.isEmpty else { return (0, []) }

        // Delete them
        let deleteSQL: String
        if all {
            deleteSQL = "DELETE FROM reminders"
        } else if let specificID = id {
            deleteSQL = "DELETE FROM reminders WHERE id = ?"
            _ = specificID  // will rebind below
        } else {
            deleteSQL = "DELETE FROM reminders WHERE lower(text) LIKE lower(?)"
        }

        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &delStmt, nil) == SQLITE_OK {
            if let p = boundParam {
                sqlite3_bind_text(delStmt, 1, p, -1, SQLITE_TRANSIENT)
            }
            sqlite3_step(delStmt)
        }
        sqlite3_finalize(delStmt)

        return (toDelete.count, toDelete)
    }

    public func loadActiveReminders() throws -> [Reminder] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, text, fire_at FROM reminders WHERE fired = 0 ORDER BY fire_at ASC", -1, &stmt, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        var result: [Reminder] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id   = columnText(stmt, 0)
            let text = columnText(stmt, 1)
            let ts   = Double(sqlite3_column_int64(stmt, 2))
            result.append(Reminder(id: id, text: text,
                                   fireAt: Date(timeIntervalSince1970: ts), fired: false))
        }
        return result
    }

    public func listAllReminders() throws -> [Reminder] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, text, fire_at, fired FROM reminders ORDER BY fire_at ASC", -1, &stmt, nil) == SQLITE_OK else {
            throw DataStoreError.prepareFailed(lastError())
        }
        defer { sqlite3_finalize(stmt) }
        var result: [Reminder] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id   = columnText(stmt, 0)
            let text = columnText(stmt, 1)
            let ts   = Double(sqlite3_column_int64(stmt, 2))
            let fired = sqlite3_column_int64(stmt, 3) != 0
            result.append(Reminder(id: id, text: text,
                                   fireAt: Date(timeIntervalSince1970: ts), fired: fired))
        }
        return result
    }

    // ─── Helpers ──────────────────────────────────────────

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    private func lastError() -> String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
    }
}
