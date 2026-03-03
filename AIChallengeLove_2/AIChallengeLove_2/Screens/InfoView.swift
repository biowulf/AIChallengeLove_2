//
//  InfoView.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/15/25.
//

import SwiftUI

struct InfoView: View {
    @Bindable var viewModel: ChatDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // MARK: - Настройки запроса
                Text("Настройки:")
                    .font(.title)
                    .padding(.bottom, 6)

                HStack {
                    Text("Max Tokens:")
                        .font(.headline)
                    TextField("не ограничено", text: $viewModel.maxTokensText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                        .onChange(of: viewModel.maxTokensText) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue {
                                viewModel.maxTokensText = filtered
                            }
                        }
                }
                .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Temperature: \(String(format: "%.2f", viewModel.temperature))")
                        .font(.headline)
                    Slider(value: $viewModel.temperature, in: 0...2, step: 0.01)
                        .tint(.blue)
                }
                .padding(.bottom, 20)

                Divider()
                    .padding(.bottom, 10)

                // MARK: - Контекст
                Text("Контекст:")
                    .font(.title)
                    .padding(.bottom, 6)

                Text("Режим: \(viewModel.contextStrategy.label)")
                    .font(.headline)
                    .padding(.bottom, 10)

                // Настройка размера окна (для slidingWindow и stickyFacts)
                if viewModel.contextStrategy == .slidingWindow || viewModel.contextStrategy == .stickyFacts {
                    windowSizeSection
                }

                // Факты (для stickyFacts)
                if viewModel.contextStrategy == .stickyFacts {
                    factsSection
                }

                // Информация о суммаризации (для gptSummary)
                if viewModel.contextStrategy == .gptSummary && !viewModel.summaries.isEmpty {
                    summarySection
                }

                // Информация о ветках (для branching)
                if viewModel.contextStrategy == .branching {
                    branchInfoSection
                }

                Text("Всего сообщений: \(viewModel.effectiveMessages().count)")
                    .padding(.bottom, 10)

                Divider()
                    .padding(.bottom, 10)

                // MARK: - Статистика
                Text("За запрос:")
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("GPT: \(viewModel.gptAPI.rawValue)")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("Исходящие: \(viewModel.info.request[viewModel.gptAPI]?.input ?? 0)")
                Text("Моделью: \(viewModel.info.request[viewModel.gptAPI]?.output ?? 0)")
                Text("Всего токенов: \(viewModel.info.request[viewModel.gptAPI]?.total ?? 0)")
                    .padding(.bottom, 30)

                Text("За сессию:")
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("GPT: \(viewModel.gptAPI.rawValue)")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("Исходящие: \(viewModel.info.session[viewModel.gptAPI]?.input ?? 0)")
                Text("Моделью: \(viewModel.info.session[viewModel.gptAPI]?.output ?? 0)")
                Text("Всего токенов: \(viewModel.info.session[viewModel.gptAPI]?.total ?? 0)")

                Button("Сбросить сессию") {
                    viewModel.clearSessionStats()
                }
                .padding(.top)
                .padding(.bottom, 30)

                Text("За всё время:")
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("GPT: \(viewModel.gptAPI.rawValue)")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("Исходящие: \(viewModel.info.appSession[viewModel.gptAPI]?.input ?? 0)")
                Text("Моделью: \(viewModel.info.appSession[viewModel.gptAPI]?.output ?? 0)")
                Text("Всего токенов: \(viewModel.info.appSession[viewModel.gptAPI]?.total ?? 0)")

                Spacer()
            }
            .padding()
        }
        .background(Color.mint.opacity(0.2))
        .frame(width: 270)
    }

    // MARK: - Window Size

    private var windowSizeSection: some View {
        HStack {
            Text("Окно (N):")
                .font(.headline)
            TextField("10", text: $viewModel.windowSizeText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 60)
                .onChange(of: viewModel.windowSizeText) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue {
                        viewModel.windowSizeText = filtered
                    }
                    if let n = Int(filtered), n > 0 {
                        viewModel.contextWindowSize = n
                    }
                }
        }
        .padding(.bottom, 10)
    }

    // MARK: - Sticky Facts

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.facts.isEmpty {
                Text("Фактов пока нет")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Ключевые факты (\(viewModel.facts.count)):")
                    .font(.headline)

                ForEach(viewModel.facts) { fact in
                    HStack(alignment: .top, spacing: 4) {
                        Text(fact.key + ":")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        Text(fact.value)
                            .font(.caption)
                    }
                }

                Button("Очистить факты") {
                    viewModel.clearFacts()
                }
                .font(.caption)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - GPT Summary Info

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Резюме: \(viewModel.summaries.count)")
            Text("Сообщений сжато: \(viewModel.summarizedUpToIndex)")
        }
        .padding(.bottom, 10)
    }

    // MARK: - Dialog Lines Info

    private var branchInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Линий диалога: \(viewModel.dialogLines.count)")
            if let lineId = viewModel.activeLineId,
               let line = viewModel.dialogLines.first(where: { $0.id == lineId }) {
                Text("Активная: \(line.topic)")
                    .fontWeight(.bold)
                Text("Сообщений в линии: \(line.messages.count)")
            } else {
                Text("Активная: нет")
            }

            if !viewModel.dialogLines.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(viewModel.dialogLines) { line in
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: viewModel.activeLineId == line.id
                              ? "circle.fill" : "circle")
                            .font(.system(size: 6))
                            .foregroundColor(viewModel.activeLineId == line.id
                                             ? .accentColor : .secondary)
                            .padding(.top, 4)
                        Text("\(line.topic) (\(line.messages.count))")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.bottom, 10)
    }
}
