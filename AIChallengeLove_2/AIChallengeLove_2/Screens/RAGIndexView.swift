//
//  RAGIndexView.swift
//  AIChallengeLove_2
//
//  Created by Bolyachev Rostislav on 3/22/26.
//

import SwiftUI

struct RAGIndexView: View {
    @Bindable var viewModel: RAGIndexViewModel

    @Binding var isRAGEnabled: Bool
    @Binding var ragTopK: Int
    @Binding var ragScoreThreshold: Float
    @Binding var ragFilterStrategy: ChunkStrategy?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerSection
                Divider()
                pipelineSection
                Divider()
                importSection
                Divider()
                statsSection
                Divider()
                searchSection
                if !viewModel.searchResults.isEmpty {
                    Divider()
                    resultsSection
                }
                Divider()
                browseSection
                Divider()
                dangerSection
            }
            .padding(12)
        }
        .frame(width: 320)
        .background(Color.purple.opacity(0.04))
    }

    // MARK: - Хедер

    private var headerSection: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.purple)
            Text("RAG Индекс")
                .font(.headline)
            Spacer()
            Circle()
                .fill(viewModel.isOllamaAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(viewModel.isOllamaAvailable ? "Ollama ✓" : "Ollama ✗")
                .font(.caption2)
                .foregroundStyle(viewModel.isOllamaAvailable ? .green : .red)
        }
    }

    // MARK: - Pipeline

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RAG Pipeline").font(.subheadline).bold()
                Spacer()
                Toggle("", isOn: $isRAGEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(.purple)
            }

            if isRAGEnabled {
                HStack {
                    Text("Топ-K чанков")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper("\(ragTopK)", value: $ragTopK, in: 1...20)
                        .font(.caption)
                }

                HStack(spacing: 6) {
                    Text("Мин. score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $ragScoreThreshold, in: 0.5...0.95, step: 0.01)
                        .tint(.purple)
                    Text(String(format: "%.2f", ragScoreThreshold))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Стратегия поиска")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $ragFilterStrategy) {
                        Text("Все").tag(ChunkStrategy?.none)
                        Text("Фикс.").tag(ChunkStrategy?.some(.fixedSize))
                        Text("Структурная").tag(ChunkStrategy?.some(.structural))
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.totalIndexed == 0 {
                    Label("Индекс пуст — загрузи документы", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if !viewModel.isOllamaAvailable {
                    Label("Ollama недоступна — запусти локально", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(8)
        .background(isRAGEnabled ? Color.purple.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Импорт

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Импорт").font(.subheadline).bold()

            Button(action: { viewModel.openDirectoryPicker() }) {
                Label("Выбрать директорию...", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isIndexing || !viewModel.isOllamaAvailable)

            if viewModel.isIndexing {
                progressSection
            }

            if let info = viewModel.infoMessage {
                Text(info)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let err = viewModel.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Двойной прогресс-бар

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {

            // — Общий прогресс по файлам —
            let fCur = viewModel.fileProgress.current
            let fTot = viewModel.fileProgress.total

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Файлы")
                        .font(.caption2).bold()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(fCur) / \(fTot)")
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(fCur), total: Double(max(fTot, 1)))
                    .tint(.purple)
            }

            // — Текущий файл —
            if !viewModel.currentFileName.isEmpty {
                Text(viewModel.currentFileName)
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // — Прогресс чанков текущего файла —
            let cCur = viewModel.chunkProgress.current
            let cTot = viewModel.chunkProgress.total

            if cTot > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Чанки")
                            .font(.caption2).bold()
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(cCur) / \(cTot)")
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(cCur), total: Double(max(cTot, 1)))
                        .tint(.blue)
                }
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Статистика

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Сравнение стратегий").font(.subheadline).bold()
                Spacer()
                Text("Всего: \(viewModel.totalIndexed)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            strategyRow(label: "Фикс. размер (500/75)",
                        stats: viewModel.statsFixed,
                        color: .blue)

            strategyRow(label: "Структурная (заголовки)",
                        stats: viewModel.statsStructural,
                        color: .orange)

            Button("Обновить") { viewModel.refreshStats() }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }

    private func strategyRow(label: String, stats: IndexStats?, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).bold()
                if let s = stats {
                    Text("\(s.count) чанков · avg \(Int(s.avgChars)) · min \(s.minChars) · max \(s.maxChars)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("нет данных").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(6)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Поиск

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Семантический поиск").font(.subheadline).bold()

            HStack {
                TextField("Запрос...", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.search() } }

                Button {
                    Task { await viewModel.search() }
                } label: {
                    if viewModel.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(viewModel.isSearching || viewModel.searchQuery.isEmpty)
            }

            Picker("Стратегия", selection: $viewModel.filterStrategy) {
                Text("Все").tag(ChunkStrategy?.none)
                Text("Фикс.").tag(ChunkStrategy?.some(.fixedSize))
                Text("Структурная").tag(ChunkStrategy?.some(.structural))
            }
            .pickerStyle(.segmented)
            .font(.caption)
        }
    }

    // MARK: - Результаты

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Топ-\(viewModel.searchResults.count) результатов")
                .font(.subheadline).bold()

            ForEach(Array(viewModel.searchResults.enumerated()), id: \.offset) { idx, pair in
                let (chunk, score) = pair
                resultCard(chunk: chunk, score: score, rank: idx + 1)
            }
        }
    }

    private func resultCard(chunk: DocumentChunk, score: Float, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(rank)")
                    .font(.caption2).bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(scoreColor(score))
                    .clipShape(Capsule())

                Text(String(format: "%.3f", score))
                    .font(.caption2).bold()
                    .foregroundStyle(scoreColor(score))

                Spacer()

                Text(chunk.metadata.strategy == .fixedSize ? "Fix" : "Str")
                    .font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(chunk.metadata.strategy == .fixedSize
                        ? Color.blue.opacity(0.15)
                        : Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text(chunk.metadata.section)
                .font(.caption).bold()
                .lineLimit(1)

            Text(chunk.metadata.source)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(chunk.content.prefix(120) + (chunk.content.count > 120 ? "…" : ""))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(8)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func scoreColor(_ score: Float) -> Color {
        switch score {
        case 0.85...: return .green
        case 0.7..<0.85: return .orange
        default: return .gray
        }
    }

    // MARK: - Браузер базы

    @State private var isBrowseExpanded = false

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Заголовок-аккордеон
            Button {
                isBrowseExpanded.toggle()
                if isBrowseExpanded { viewModel.loadBrowseChunks() }
            } label: {
                HStack {
                    Image(systemName: isBrowseExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Просмотр базы")
                        .font(.subheadline).bold()
                    Spacer()
                    if viewModel.totalIndexed > 0 {
                        Text("\(viewModel.totalIndexed) записей")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isBrowseExpanded {
                // Фильтр по стратегии
                Picker("", selection: $viewModel.browseStrategy) {
                    Text("Все").tag(ChunkStrategy?.none)
                    Text("Fix").tag(ChunkStrategy?.some(.fixedSize))
                    Text("Str").tag(ChunkStrategy?.some(.structural))
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.browseStrategy) { _, _ in
                    viewModel.loadBrowseChunks()
                }

                if viewModel.browseChunks.isEmpty {
                    Text("Нет данных")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    // Группируем по файлу (source)
                    let grouped = Dictionary(grouping: viewModel.browseChunks, by: { $0.metadata.source })
                    let sources = grouped.keys.sorted()

                    ForEach(sources, id: \.self) { source in
                        let chunks = grouped[source] ?? []
                        sourceGroup(source: source, chunks: chunks)
                    }
                }
            }
        }
    }

    private func sourceGroup(source: String, chunks: [DocumentChunk]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Заголовок файла
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text(source)
                    .font(.caption).bold()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(chunks.count)")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.purple)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color.purple.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Чанки файла
            ForEach(chunks) { chunk in
                chunkRow(chunk: chunk)
            }
        }
    }

    private func chunkRow(chunk: DocumentChunk) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // chunk_id (укороченный)
            HStack(spacing: 4) {
                Text("ID")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(String(chunk.metadata.chunkId.prefix(8)) + "…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                // Стратегия
                Text(chunk.metadata.strategy == .fixedSize ? "Fix" : "Str")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(chunk.metadata.strategy == .fixedSize ? Color.blue : Color.orange)
                    .clipShape(Capsule())
                // Эмбеддинг
                Image(systemName: chunk.embedding != nil ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption2)
                    .foregroundStyle(chunk.embedding != nil ? Color.green : Color.gray)
            }

            // title + section
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    metaRow(key: "title",   value: chunk.metadata.title)
                    metaRow(key: "section", value: chunk.metadata.section)
                    metaRow(key: "idx",     value: "#\(chunk.metadata.chunkIndex)  offset \(chunk.metadata.charOffset)")
                    metaRow(key: "chars",   value: "\(chunk.content.count)  emb: \(chunk.embedding.map { "\($0.count)d" } ?? "—")")
                }
            }

            // Превью контента
            Text(chunk.content.prefix(80) + (chunk.content.count > 80 ? "…" : ""))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(4)
                .background(Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(6)
        .background(Color.gray.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.gray.opacity(0.12), lineWidth: 1)
        )
    }

    private func metaRow(key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.system(size: 9))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Очистка

    private var dangerSection: some View {
        Button(role: .destructive) {
            viewModel.clearIndex()
        } label: {
            Label("Очистить весь индекс", systemImage: "trash")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(viewModel.isIndexing || viewModel.totalIndexed == 0)
    }
}
