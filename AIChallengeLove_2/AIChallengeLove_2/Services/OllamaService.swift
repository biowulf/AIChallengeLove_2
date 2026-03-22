//
//  OllamaService.swift
//  AIChallengeLove_2
//
//  Created by Bolyachev Rostislav on 3/22/26.
//

import Foundation
import Alamofire

// MARK: - Ошибки

enum OllamaError: LocalizedError {
    case emptyEmbedding
    case serverUnreachable
    case decodingFailed(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyEmbedding:        return "Ollama вернул пустой вектор"
        case .serverUnreachable:     return "Ollama недоступен (localhost:11434)"
        case .decodingFailed(let m): return "Ошибка ответа Ollama: \(m)"
        case .encodingFailed:        return "Ошибка кодирования запроса"
        }
    }
}

// MARK: - Сервис

final class OllamaService: Sendable {
    static let shared = OllamaService()

    private let baseURL = "http://localhost:11434"
    private let modelName = "nomic-embed-text"

    // Используем Alamofire Session (без лишних interceptor'ов)
    private let session: Session

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        session = Session(configuration: config)
    }

    // MARK: - Одиночный эмбеддинг

    func embed(text: String) async throws -> [Float] {
        let bodyDict: [String: Any] = ["model": modelName, "prompt": text]
        guard let data = try? JSONSerialization.data(withJSONObject: bodyDict) else {
            throw OllamaError.encodingFailed
        }

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/api/embeddings")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = data

        let responseData = try await session
            .request(urlRequest)
            .validate()
            .serializingData()
            .value

        do {
            guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let embedding = json["embedding"] as? [Double]
            else { throw OllamaError.decodingFailed("неожиданная структура ответа") }

            guard !embedding.isEmpty else { throw OllamaError.emptyEmbedding }
            return embedding.map { Float($0) }
        } catch let e as OllamaError {
            throw e
        } catch {
            throw OllamaError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Пакетный эмбеддинг

    func embedBatch(
        chunks: [DocumentChunk],
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [DocumentChunk] {
        var result: [DocumentChunk] = []
        result.reserveCapacity(chunks.count)

        for (index, chunk) in chunks.enumerated() {
            var updated = chunk
            updated.embedding = try await embed(text: chunk.content)
            result.append(updated)
            progress(index + 1, chunks.count)
        }

        return result
    }

    // MARK: - Проверка доступности

    func ping() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        let response = await session
            .request(url)
            .validate()
            .serializingData()
            .response
        return response.response?.statusCode == 200
    }
}
