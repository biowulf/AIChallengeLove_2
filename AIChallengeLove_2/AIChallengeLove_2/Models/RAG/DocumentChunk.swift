//
//  DocumentChunk.swift
//  AIChallengeLove_2
//
//  Created by Bolyachev Rostislav on 3/22/26.
//

import Foundation

// MARK: - Стратегия чанкинга

enum ChunkStrategy: String, Codable, CaseIterable {
    case fixedSize   = "fixedSize"
    case structural  = "structural"

    var displayName: String {
        switch self {
        case .fixedSize:  return "Фикс. размер (500/75)"
        case .structural: return "Структурная (заголовки)"
        }
    }
}

// MARK: - Метаданные чанка

struct ChunkMetadata: Codable, Equatable {
    var chunkId: String         // UUID
    var source: String          // имя файла
    var title: String           // имя файла без расширения
    var section: String         // заголовок секции или "Чанк N"
    var strategy: ChunkStrategy
    var charOffset: Int         // позиция начала в оригинальном тексте
    var chunkIndex: Int         // порядковый номер чанка в документе
    var createdAt: Date

    init(source: String, section: String, strategy: ChunkStrategy,
         charOffset: Int, chunkIndex: Int) {
        self.chunkId = UUID().uuidString
        self.source = source
        self.title = URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
        self.section = section
        self.strategy = strategy
        self.charOffset = charOffset
        self.chunkIndex = chunkIndex
        self.createdAt = Date()
    }
}

// MARK: - Чанк документа

struct DocumentChunk: Identifiable {
    var id: String { metadata.chunkId }
    var content: String
    var metadata: ChunkMetadata
    var embedding: [Float]?     // 768-мерный вектор nomic-embed-text, nil до эмбеддинга
}

// MARK: - Статистика индекса

struct IndexStats {
    var strategy: ChunkStrategy
    var count: Int
    var totalChars: Int
    var avgChars: Double
    var minChars: Int
    var maxChars: Int

    var description: String {
        "\(count) чанков, avg \(Int(avgChars)) / min \(minChars) / max \(maxChars) символов"
    }
}
