//
//  DocumentChunker.swift
//  AIChallengeLove_2
//
//  Created by Bolyachev Rostislav on 3/22/26.
//

import Foundation

// MARK: - Протокол

protocol ChunkingStrategyProtocol {
    var strategyType: ChunkStrategy { get }
    func chunk(text: String, source: String) -> [DocumentChunk]
}

// MARK: - Стратегия 1: Фиксированный размер с перекрытием

/// Нарезает текст скользящим окном по символам.
/// Разрыв всегда делается на границе слова, чтобы не резать посередине.
struct FixedSizeChunker: ChunkingStrategyProtocol {
    let strategyType: ChunkStrategy = .fixedSize
    var chunkSize: Int = 500
    var overlap: Int = 75

    func chunk(text: String, source: String) -> [DocumentChunk] {
        guard !text.isEmpty else { return [] }

        var chunks: [DocumentChunk] = []
        let chars = Array(text)
        var start = 0
        var chunkIndex = 0

        while start < chars.count {
            let rawEnd = min(start + chunkSize, chars.count)

            // Ищем границу слова: сдвигаемся назад от rawEnd до ближайшего пробела/переноса
            var end = rawEnd
            if end < chars.count {
                while end > start + 1 && !chars[end - 1].isWhitespace {
                    end -= 1
                }
                if end == start + 1 { end = rawEnd } // нет пробела — режем жёстко
            }

            let content = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                let meta = ChunkMetadata(
                    source: source,
                    section: "Чанк \(chunkIndex + 1)",
                    strategy: .fixedSize,
                    charOffset: start,
                    chunkIndex: chunkIndex
                )
                chunks.append(DocumentChunk(content: content, metadata: meta))
                chunkIndex += 1
            }

            // Следующий старт — с перекрытием назад
            let nextStart = end - overlap
            start = nextStart > start ? nextStart : end  // защита от бесконечного цикла
        }

        return chunks
    }
}

// MARK: - Стратегия 2: Структурная (по заголовкам markdown / разделам)

/// Делит текст по заголовкам markdown (#, ##, ###) и крупным пустым блокам.
/// Каждый раздел становится отдельным чанком; очень большие разделы (>1500 символов)
/// дополнительно делятся по абзацам.
struct StructuralChunker: ChunkingStrategyProtocol {
    let strategyType: ChunkStrategy = .structural
    var maxSectionSize: Int = 1500

    func chunk(text: String, source: String) -> [DocumentChunk] {
        guard !text.isEmpty else { return [] }

        let lines = text.components(separatedBy: "\n")
        var sections: [(title: String, body: String, offset: Int)] = []
        var currentTitle = "Начало"
        var currentLines: [String] = []
        var currentOffset = 0
        var runningOffset = 0

        for line in lines {
            let isHeading = line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("### ")
            if isHeading && !currentLines.isEmpty {
                sections.append((title: currentTitle,
                                 body: currentLines.joined(separator: "\n"),
                                 offset: currentOffset))
                currentTitle = String(line.drop(while: { $0 == "#" || $0 == " " }))
                currentLines = []
                currentOffset = runningOffset
            } else if isHeading {
                currentTitle = String(line.drop(while: { $0 == "#" || $0 == " " }))
                currentOffset = runningOffset
            } else {
                currentLines.append(line)
            }
            runningOffset += line.count + 1  // +1 за \n
        }
        // последняя секция
        if !currentLines.isEmpty {
            sections.append((title: currentTitle,
                             body: currentLines.joined(separator: "\n"),
                             offset: currentOffset))
        }

        var chunks: [DocumentChunk] = []
        var chunkIndex = 0

        for section in sections {
            let body = section.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }

            if body.count <= maxSectionSize {
                let meta = ChunkMetadata(
                    source: source,
                    section: section.title,
                    strategy: .structural,
                    charOffset: section.offset,
                    chunkIndex: chunkIndex
                )
                chunks.append(DocumentChunk(content: body, metadata: meta))
                chunkIndex += 1
            } else {
                // Большой раздел — разбиваем по абзацам (двойной перенос строки)
                let paragraphs = body.components(separatedBy: "\n\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                var paraOffset = section.offset
                for (pIdx, para) in paragraphs.enumerated() {
                    let meta = ChunkMetadata(
                        source: source,
                        section: "\(section.title) §\(pIdx + 1)",
                        strategy: .structural,
                        charOffset: paraOffset,
                        chunkIndex: chunkIndex
                    )
                    chunks.append(DocumentChunk(content: para, metadata: meta))
                    chunkIndex += 1
                    paraOffset += para.count + 2  // +2 за \n\n
                }
            }
        }

        // Если заголовков нет — делим по двойным переносам (как у prose/code без md)
        if chunks.isEmpty {
            let paragraphs = text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var offset = 0
            for (idx, para) in paragraphs.enumerated() {
                let meta = ChunkMetadata(
                    source: source,
                    section: "Параграф \(idx + 1)",
                    strategy: .structural,
                    charOffset: offset,
                    chunkIndex: idx
                )
                chunks.append(DocumentChunk(content: para, metadata: meta))
                offset += para.count + 2
            }
        }

        return chunks
    }
}

// MARK: - Фасад

/// Удобная обёртка — применяет обе стратегии и возвращает словарь результатов.
struct DocumentChunkerFacade {
    static let fixed = FixedSizeChunker()
    static let structural = StructuralChunker()

    static func chunkBoth(text: String, source: String) -> [ChunkStrategy: [DocumentChunk]] {
        [
            .fixedSize:  fixed.chunk(text: text, source: source),
            .structural: structural.chunk(text: text, source: source)
        ]
    }

    static func stats(for chunks: [DocumentChunk], strategy: ChunkStrategy) -> IndexStats {
        guard !chunks.isEmpty else {
            return IndexStats(strategy: strategy, count: 0, totalChars: 0,
                              avgChars: 0, minChars: 0, maxChars: 0)
        }
        let sizes = chunks.map { $0.content.count }
        let total = sizes.reduce(0, +)
        return IndexStats(
            strategy: strategy,
            count: chunks.count,
            totalChars: total,
            avgChars: Double(total) / Double(chunks.count),
            minChars: sizes.min() ?? 0,
            maxChars: sizes.max() ?? 0
        )
    }
}
