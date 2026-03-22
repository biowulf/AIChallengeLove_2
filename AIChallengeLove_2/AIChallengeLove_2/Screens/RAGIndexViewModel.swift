//
//  RAGIndexViewModel.swift
//  AIChallengeLove_2
//
//  Created by Bolyachev Rostislav on 3/22/26.
//

import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

@Observable
@MainActor
final class RAGIndexViewModel {

    // MARK: - Состояние индексации

    var isIndexing = false

    /// Общий прогресс: сколько файлов обработано из общего числа
    var fileProgress: (current: Int, total: Int) = (0, 0)

    /// Прогресс чанков внутри текущего файла
    var chunkProgress: (current: Int, total: Int) = (0, 0)

    /// Имя файла, который индексируется прямо сейчас
    var currentFileName: String = ""

    var isOllamaAvailable = false

    // MARK: - Статистика

    var statsFixed: IndexStats?
    var statsStructural: IndexStats?
    var totalIndexed: Int = 0

    // MARK: - Поиск

    var searchQuery = ""
    var searchResults: [(DocumentChunk, Float)] = []
    var isSearching = false
    var filterStrategy: ChunkStrategy? = nil

    // MARK: - Браузер базы

    var browseChunks: [DocumentChunk] = []
    var browseStrategy: ChunkStrategy? = nil   // nil = все
    var isBrowseLoaded = false

    // MARK: - Ошибки / уведомления

    var errorMessage: String?
    var infoMessage: String?

    // MARK: - Приватные сервисы

    @ObservationIgnored private let ragIndex = RAGIndex()
    @ObservationIgnored private let ollama = OllamaService.shared

    // Расширения файлов, которые считаем текстом
    private let supportedExtensions: Set<String> = [
        "swift", "txt", "md", "markdown", "json", "yaml", "yml",
        "py", "js", "ts", "kt", "java", "c", "cpp", "h", "hpp",
        "html", "css", "xml", "sh", "rb", "go", "rs", "toml"
    ]

    // MARK: - Init

    init() {
        refreshStats()
        Task { await checkOllama() }
    }

    // MARK: - Проверка Ollama

    func checkOllama() async {
        isOllamaAvailable = await ollama.ping()
    }

    // MARK: - Выбор директории

    func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Выберите директорию для индексации"
        panel.prompt = "Индексировать"

        if panel.runModal() == .OK, let url = panel.url {
            Task { await indexDirectory(url: url) }
        }
    }

    // MARK: - Индексация директории

    func indexDirectory(url: URL) async {
        guard !isIndexing else { return }
        errorMessage = nil
        infoMessage = nil

        // Собираем все подходящие файлы рекурсивно
        let files = collectFiles(in: url)
        guard !files.isEmpty else {
            infoMessage = "В директории нет текстовых файлов"
            return
        }

        isIndexing = true
        fileProgress = (0, files.count)
        chunkProgress = (0, 0)
        currentFileName = ""

        var totalFixed = 0
        var totalStructural = 0
        var skipped = 0

        for (fileIndex, fileURL) in files.enumerated() {
            currentFileName = fileURL.lastPathComponent
            fileProgress = (fileIndex, files.count)

            // Читаем файл
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                skipped += 1
                continue
            }

            let source = fileURL.lastPathComponent

            // Чанкинг обеими стратегиями
            let allChunks = DocumentChunkerFacade.chunkBoth(text: text, source: source)
            let fixedChunks = allChunks[.fixedSize] ?? []
            let structChunks = allChunks[.structural] ?? []
            let combined = fixedChunks + structChunks

            chunkProgress = (0, combined.count)

            do {
                let embedded = try await ollama.embedBatch(chunks: combined) { [weak self] cur, tot in
                    Task { @MainActor [weak self] in
                        self?.chunkProgress = (cur, tot)
                    }
                }
                try ragIndex.insertBatch(chunks: embedded)
                totalFixed += fixedChunks.count
                totalStructural += structChunks.count
            } catch {
                // Логируем ошибку, но продолжаем с остальными файлами
                errorMessage = "\(source): \(error.localizedDescription)"
            }
        }

        // Завершение
        fileProgress = (files.count, files.count)
        currentFileName = ""
        refreshStats()

        var summary = "✓ \(files.count - skipped) файлов · \(totalFixed) fix + \(totalStructural) str чанков"
        if skipped > 0 { summary += " · пропущено \(skipped)" }
        infoMessage = summary

        isIndexing = false
        fileProgress = (0, 0)
        chunkProgress = (0, 0)
    }

    // MARK: - Сбор файлов из директории (рекурсивно)

    private func collectFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            // Пропускаем скрытые файлы и системные директории
            let name = url.lastPathComponent
            if name.hasPrefix(".") { continue }
            if name == "DerivedData" || name == ".build" || name == "node_modules" { continue }

            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
               values.isRegularFile == true {
                result.append(url)
            }
        }
        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Поиск

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching else { return }
        errorMessage = nil

        isSearching = true
        do {
            let queryEmbedding = try await ollama.embed(text: query)
            let results = try ragIndex.search(queryEmbedding: queryEmbedding,
                                              topK: 5,
                                              strategy: filterStrategy)
            searchResults = results
            infoMessage = results.isEmpty
                ? "Результатов нет — попробуйте другой запрос"
                : nil
        } catch {
            errorMessage = "Поиск: \(error.localizedDescription)"
        }
        isSearching = false
    }

    // MARK: - Очистка

    func clearIndex() {
        do {
            try ragIndex.clearAll()
            searchResults = []
            statsFixed = nil
            statsStructural = nil
            totalIndexed = 0
            infoMessage = "Индекс очищен"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Браузер базы

    func loadBrowseChunks() {
        browseChunks = (try? ragIndex.allChunks(strategy: browseStrategy)) ?? []
        isBrowseLoaded = true
    }

    // MARK: - Статистика

    func refreshStats() {
        totalIndexed    = ragIndex.totalCount()
        statsFixed      = try? ragIndex.stats(strategy: .fixedSize)
        statsStructural = try? ragIndex.stats(strategy: .structural)
    }
}
