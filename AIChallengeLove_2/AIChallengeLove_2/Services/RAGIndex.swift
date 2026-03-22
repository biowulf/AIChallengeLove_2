//
//  RAGIndex.swift
//  AIChallengeLove_2
//
//  Created by Bolyachev Rostislav on 3/22/26.
//

import Foundation
import SQLite3

// MARK: - Ошибки

enum RAGIndexError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case insertFailed(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .openFailed(let m):    return "SQLite open: \(m)"
        case .prepareFailed(let m): return "SQLite prepare: \(m)"
        case .insertFailed(let m):  return "SQLite insert: \(m)"
        case .encodingFailed:       return "Ошибка кодирования метаданных"
        }
    }
}

// MARK: - RAGIndex

final class RAGIndex {

    // MARK: - Инициализация

    private var db: OpaquePointer?

    init() {
        do { try openDatabase() }
        catch { print("RAGIndex: не удалось открыть БД: \(error)") }
    }

    deinit { sqlite3_close(db) }

    // MARK: - БД

    private func openDatabase() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AIChallengeLove2", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("rag.sqlite")

        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            throw RAGIndexError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try createTables()
    }

    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS chunks (
            chunk_id    TEXT PRIMARY KEY,
            content     TEXT NOT NULL,
            metadata    TEXT NOT NULL,
            embedding   BLOB,
            created_at  REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_source ON chunks(
            json_extract(metadata, '$.source')
        );
        CREATE INDEX IF NOT EXISTS idx_strategy ON chunks(
            json_extract(metadata, '$.strategy')
        );
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw RAGIndexError.prepareFailed(msg)
        }
    }

    // MARK: - CRUD

    func insertBatch(chunks: [DocumentChunk]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        let sql = """
        INSERT OR REPLACE INTO chunks (chunk_id, content, metadata, embedding, created_at)
        VALUES (?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RAGIndexError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

        for chunk in chunks {
            guard let metaData = try? encoder.encode(chunk.metadata),
                  let metaStr = String(data: metaData, encoding: .utf8)
            else { throw RAGIndexError.encodingFailed }

            sqlite3_bind_text(stmt, 1, chunk.metadata.chunkId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, chunk.content,          -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, metaStr,                -1, SQLITE_TRANSIENT)

            // Embedding → BLOB (Float32 little-endian)
            if let emb = chunk.embedding {
                var floats = emb
                let byteCount = floats.count * MemoryLayout<Float>.size
                floats.withUnsafeBytes { ptr in
                    _ = sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(byteCount), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(stmt, 4)
            }

            sqlite3_bind_double(stmt, 5, chunk.metadata.createdAt.timeIntervalSince1970)

            if sqlite3_step(stmt) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw RAGIndexError.insertFailed(msg)
            }
            sqlite3_reset(stmt)
        }

        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    func deleteBySource(source: String) throws {
        let sql = "DELETE FROM chunks WHERE json_extract(metadata, '$.source') = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RAGIndexError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, source, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    func clearAll() throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, "DELETE FROM chunks;", nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw RAGIndexError.prepareFailed(msg)
        }
    }

    // MARK: - Загрузка

    func allChunks(strategy: ChunkStrategy? = nil) throws -> [DocumentChunk] {
        let sql: String
        if let s = strategy {
            sql = "SELECT chunk_id, content, metadata, embedding FROM chunks WHERE json_extract(metadata, '$.strategy') = '\(s.rawValue)';"
        } else {
            sql = "SELECT chunk_id, content, metadata, embedding FROM chunks;"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw RAGIndexError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var chunks: [DocumentChunk] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let contentPtr = sqlite3_column_text(stmt, 1),
                  let metaPtr    = sqlite3_column_text(stmt, 2)
            else { continue }

            let content  = String(cString: contentPtr)
            let metaStr  = String(cString: metaPtr)

            guard let metaData = metaStr.data(using: .utf8),
                  let meta = try? decoder.decode(ChunkMetadata.self, from: metaData)
            else { continue }

            var embedding: [Float]? = nil
            if sqlite3_column_type(stmt, 3) == SQLITE_BLOB {
                let byteCount = sqlite3_column_bytes(stmt, 3)
                if let ptr = sqlite3_column_blob(stmt, 3) {
                    let floatCount = Int(byteCount) / MemoryLayout<Float>.size
                    embedding = Array(UnsafeBufferPointer(
                        start: ptr.assumingMemoryBound(to: Float.self),
                        count: floatCount
                    ))
                }
            }

            chunks.append(DocumentChunk(content: content, metadata: meta, embedding: embedding))
        }

        return chunks
    }

    // MARK: - Статистика

    func stats(strategy: ChunkStrategy) throws -> IndexStats {
        let chunks = try allChunks(strategy: strategy)
        return DocumentChunkerFacade.stats(for: chunks, strategy: strategy)
    }

    func totalCount() -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM chunks;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    // MARK: - Поиск по косинусному сходству

    /// Загружает все чанки с эмбеддингами, считает косинусное сходство, возвращает топ-K.
    func search(queryEmbedding: [Float], topK: Int = 5, strategy: ChunkStrategy? = nil) throws -> [(DocumentChunk, Float)] {
        let all = try allChunks(strategy: strategy).filter { $0.embedding != nil }
        guard !all.isEmpty else { return [] }

        var scored: [(DocumentChunk, Float)] = all.map { chunk in
            let sim = cosineSimilarity(queryEmbedding, chunk.embedding!)
            return (chunk, sim)
        }

        scored.sort { $0.1 > $1.1 }
        return Array(scored.prefix(topK))
    }

    // MARK: - Косинусное сходство

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot  += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = normA.squareRoot() * normB.squareRoot()
        return denom > 0 ? dot / denom : 0
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
