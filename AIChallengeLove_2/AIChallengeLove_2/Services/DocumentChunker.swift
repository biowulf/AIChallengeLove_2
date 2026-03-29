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

// MARK: - Стратегия 2: Структурная (по заголовкам + Swift-декларациям)

/// Делит текст по:
/// - Markdown-заголовкам (#, ##, ###)
/// - Swift MARK-комментариям (// MARK: -)
/// - Для файлов без заголовков — по top-level декларациям (func/class/struct/enum/extension)
///   с трекингом фигурных скобок, чтобы не резать тело объявления.
///
/// Ключевое правило: заголовок секции ВКЛЮЧАЕТСЯ в тело чанка как первая строка,
/// чтобы embedding видел название раздела и поиск работал корректно.
struct StructuralChunker: ChunkingStrategyProtocol {
    let strategyType: ChunkStrategy = .structural
    var maxSectionSize: Int = 2000
    var minChunkSize: Int = 80

    // Ключевые слова, которые начинают top-level декларацию в Swift/других языках
    private static let topLevelKeywords = [
        "func ", "private func ", "public func ", "internal func ", "fileprivate func ",
        "override func ", "static func ", "class func ", "open func ",
        "var ", "let ", "private var ", "private let ", "static var ", "static let ",
        "class ", "struct ", "enum ", "extension ", "protocol ",
        "typealias ", "associatedtype ", "init(", "deinit {", "subscript("
    ]

    func chunk(text: String, source: String) -> [DocumentChunk] {
        guard !text.isEmpty else { return [] }
        let lines = text.components(separatedBy: "\n")

        // Шаг 1: разбиваем на секции по заголовкам.
        // Заголовок ВКЛЮЧАЕТСЯ в тело следующей секции как первая строка.
        var rawSections: [(title: String, bodyLines: [String], offset: Int)] = []
        var currentTitle = ""
        var currentLines: [String] = []
        var currentOffset = 0
        var runningOffset = 0

        for line in lines {
            if let title = extractHeadingTitle(from: line) {
                // Сохраняем накопленные строки как секцию
                let body = currentLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if body.count >= minChunkSize {
                    rawSections.append((title: currentTitle, bodyLines: currentLines, offset: currentOffset))
                }
                // Новая секция начинается с самой строки-заголовка
                currentTitle = title
                currentLines = [line]
                currentOffset = runningOffset
            } else {
                currentLines.append(line)
            }
            runningOffset += line.count + 1
        }
        // Последняя секция
        let lastBody = currentLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if lastBody.count >= minChunkSize {
            rawSections.append((title: currentTitle, bodyLines: currentLines, offset: currentOffset))
        }

        // Если заголовков не нашли — файл без MARK/markdown (чистый код)
        // Используем brace-tracking по top-level декларациям
        if rawSections.isEmpty {
            return splitByDeclarations(lines: lines, source: source, sectionTitle: "")
        }

        // Шаг 2: каждую секцию превращаем в чанк(и)
        var chunks: [DocumentChunk] = []
        var chunkIndex = 0

        for section in rawSections {
            let body = section.bodyLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard body.count >= minChunkSize else { continue }

            if body.count <= maxSectionSize {
                // Секция умещается в один чанк
                let meta = ChunkMetadata(
                    source: source, section: section.title,
                    strategy: .structural, charOffset: section.offset, chunkIndex: chunkIndex
                )
                chunks.append(DocumentChunk(content: body, metadata: meta))
                chunkIndex += 1
            } else {
                // Большая секция: режем по top-level декларациям с brace-tracking
                let sub = splitByDeclarations(
                    lines: section.bodyLines, source: source, sectionTitle: section.title, startIndex: chunkIndex
                )
                if sub.isEmpty {
                    // Крайний fallback: весь блок одним чанком
                    let meta = ChunkMetadata(
                        source: source, section: section.title,
                        strategy: .structural, charOffset: section.offset, chunkIndex: chunkIndex
                    )
                    chunks.append(DocumentChunk(content: body, metadata: meta))
                    chunkIndex += 1
                } else {
                    chunks.append(contentsOf: sub)
                    chunkIndex += sub.count
                }
            }
        }

        return chunks
    }

    // MARK: - Вспомогательные методы

    /// Если строка является заголовком, возвращает чистый заголовок без символов разметки.
    private func extractHeadingTitle(from line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)

        // Markdown
        if t.hasPrefix("### ") { return String(t.dropFirst(4)) }
        if t.hasPrefix("## ")  { return String(t.dropFirst(3)) }
        if t.hasPrefix("# ")   { return String(t.dropFirst(2)) }

        // Swift MARK (разные варианты написания)
        if t.hasPrefix("// MARK: - ") { return String(t.dropFirst(11)) }
        if t.hasPrefix("// MARK:- ")  { return String(t.dropFirst(10)) }
        if t.hasPrefix("// MARK: ")   { return String(t.dropFirst(9)) }
        if t == "// MARK:" || t.hasPrefix("// MARK:\t") { return "—" }

        return nil
    }

    /// Разбивает список строк на чанки по top-level декларациям,
    /// отслеживая глубину фигурных скобок (brace depth).
    /// Гарантирует, что тело функции/типа не будет разрезано.
    private func splitByDeclarations(
        lines: [String],
        source: String,
        sectionTitle: String,
        startIndex: Int = 0
    ) -> [DocumentChunk] {
        var chunks: [DocumentChunk] = []
        var current: [String] = []
        var braceDepth = 0
        var chunkIndex = startIndex
        var subIdx = 1
        var baseOffset = 0
        var runningOffset = 0

        func flush() {
            let content = current.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard content.count >= minChunkSize else { current = []; return }
            let title = sectionTitle.isEmpty
                ? "Блок \(subIdx)"
                : (subIdx == 1 ? sectionTitle : "\(sectionTitle) §\(subIdx)")
            let meta = ChunkMetadata(
                source: source, section: title,
                strategy: .structural, charOffset: baseOffset, chunkIndex: chunkIndex
            )
            chunks.append(DocumentChunk(content: content, metadata: meta))
            chunkIndex += 1
            subIdx += 1
            current = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let opens  = line.filter { $0 == "{" }.count
            let closes = line.filter { $0 == "}" }.count

            // На нулевой глубине и при наличии накопленного контента:
            // если строка начинает новую top-level декларацию — завершаем предыдущий чанк
            if braceDepth == 0 && !current.isEmpty {
                let isTopLevel = Self.topLevelKeywords.contains(where: { trimmed.hasPrefix($0) })
                if isTopLevel {
                    flush()
                    baseOffset = runningOffset
                }
            }

            current.append(line)
            braceDepth = max(0, braceDepth + opens - closes)
            runningOffset += line.count + 1
        }

        flush()
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
