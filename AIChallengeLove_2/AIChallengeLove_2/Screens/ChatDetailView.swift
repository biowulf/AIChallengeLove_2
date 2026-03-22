//
//  ChatDetailView.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/2/25.
//

import SwiftUI
import SwiftData

struct ChatDetailView: View {
    @Bindable var viewModel: ChatDetailViewModel

    init(viewModel: ChatDetailViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HStack {
                chatView
                if viewModel.isShowBranches {
                    BranchPanelView(viewModel: viewModel)
                }
                if viewModel.isShowMemoryPanel {
                    MemoryPanelView(viewModel: viewModel)
                }
                if viewModel.isShowSystemPromptPanel {
                    SystemPromptPanelView(viewModel: viewModel)
                }
                if viewModel.isShowTaskPanel {
                    TaskPanelView(viewModel: viewModel)
                }
                if viewModel.isShowInfo {
                    InfoView(viewModel: viewModel)
                }
                if viewModel.isShowMCPPanel {
                    MCPSettingsView(mcpManager: viewModel.mcpManager)
                }
                if viewModel.isShowRAGPanel {
                    RAGIndexView(viewModel: viewModel.ragViewModel)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack {
            HStack {
                gptTypeButton

                if viewModel.gptAPI == .gigachat {
                    gigaChatModelButton
                }

                clearChat

                strategyButton

                Spacer()

                Toggle("Ограничение ответа", isOn: $viewModel.isStrictMode)
                    .tint(.orange)

                if viewModel.gptAPI == .gigachat {
                    Toggle("Streaming", isOn: $viewModel.useStreaming)
                        .tint(.green)
                }

                if viewModel.contextStrategy == .branching {
                    // Индикатор активной линии
                    if let lineId = viewModel.activeLineId,
                       let line = viewModel.dialogLines.first(where: { $0.id == lineId }) {
                        Text(line.topic)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }

                    Button {
                        viewModel.isShowBranches.toggle()
                    } label: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                }

                if viewModel.contextStrategy == .memoryLayers {
                    Button {
                        viewModel.isShowMemoryPanel.toggle()
                    } label: {
                        Image(systemName: "brain")
                    }
                }

                Button {
                    viewModel.isShowSystemPromptPanel.toggle()
                } label: {
                    Image(systemName: "text.bubble")
                }

                Button {
                    viewModel.isShowTaskPanel.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "checklist")
                        if viewModel.isTaskModeEnabled {
                            Circle()
                                .fill(viewModel.taskState.isActive ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -3)
                        }
                    }
                }

                Button {
                    viewModel.isShowMCPPanel.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "network")
                        if viewModel.mcpManager.isEnabled {
                            Circle()
                                .fill(viewModel.mcpManager.isConnecting ? Color.orange : Color.teal)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -3)
                        }
                    }
                }

                Button {
                    viewModel.isShowRAGPanel.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "doc.text.magnifyingglass")
                        if viewModel.ragViewModel.totalIndexed > 0 {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -3)
                        }
                    }
                }

                Button {
                    viewModel.isShowInfo.toggle()
                } label: {
                    Image(systemName: "exclamationmark.circle")
                }
                .padding()
            }
            .background(Color.gray.opacity(0.2))

            if viewModel.isStrictMode {
                Text("Режим: Формат + Лимит 20 слов + Stop-слово")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Computed helpers

    private var chatInputPlaceholder: String {
        if viewModel.isTaskModeEnabled && viewModel.taskState.isEmpty {
            return "Опишите задачу — начнётся стадия Research..."
        }
        return "Сообщение..."
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.effectiveMessages()) { message in
                        MessageBubble(message: message)
                    }

                    // Streaming сообщение
                    if viewModel.isStreaming && !viewModel.streamingText.isEmpty {
                        HStack {
                            TypewriterText(fullText: viewModel.streamingText,
                                         isComplete: viewModel.isStreamingComplete)
                                .padding()
                                .background(Color.blue.opacity(0.3))
                                .cornerRadius(10)
                            Spacer()
                        }
                    }

                    // Индикатор суммаризации
                    if viewModel.isSummarizing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Сжатие контекста...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Индикатор извлечения фактов
                    if viewModel.isExtractingFacts {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Извлечение фактов...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Индикатор классификации линии диалога
                    if viewModel.isClassifying {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Определение темы...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Индикаторы извлечения памяти (Memory Layers)
                    if viewModel.isExtractingWorkingMemory {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Анализ контекста задачи...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    if viewModel.isExtractingLongTermMemory {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Обновление долговременной памяти...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Анимированные точки ожидания
                    if viewModel.isLoading && !viewModel.isSummarizing && !viewModel.isExtractingFacts && !viewModel.isClassifying && !viewModel.isExtractingWorkingMemory && !viewModel.isExtractingLongTermMemory {
                        LoadingDots()
                    }

                    // Кнопка повтора при ошибке
                    if viewModel.lastRequestFailed {
                        HStack {
                            Spacer()
                            Button {
                                viewModel.retryLastMessage()
                            } label: {
                                Label("Повторить запрос", systemImage: "arrow.clockwise")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.15))
                                    .foregroundColor(.red)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }

            // Поле ввода и кнопка отправки
            // Enter — отправить, Shift+Enter — перенос строки
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    // Placeholder поверх поля когда пусто
                    if viewModel.inputText.isEmpty {
                        Text(chatInputPlaceholder)
                            .font(.system(size: 13))
                            .foregroundColor(Color(NSColor.placeholderTextColor))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    MultilineTextField(
                        text: $viewModel.inputText,
                        onSubmit: viewModel.sendMessage
                    )
                    .frame(minHeight: 34, maxHeight: 120)
                }
                .frame(minHeight: 34)
                .padding(.horizontal, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)

                Button(action: viewModel.sendMessage) {
                    Text("Отправить")
                        .font(.system(size: 13))
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .fixedSize()
                .disabled(viewModel.isLoading || viewModel.isStreaming || viewModel.isSummarizing || viewModel.isExtractingFacts || viewModel.isClassifying || viewModel.isExtractingWorkingMemory || viewModel.isExtractingLongTermMemory)
            }
            .padding()
        }
    }

    // MARK: - Buttons

    private var gptTypeButton: some View {
        Button {
            viewModel.isActiveDialog = true
        } label: {
            HStack {
                Text(viewModel.gptAPI.rawValue)
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .padding(.leading, 2)
            }
        }
        .padding()
        .confirmationDialog("", isPresented: $viewModel.isActiveDialog) {
            ForEach(GPTAPI.allCases, id: \.self) { api in
                Button(role: (api == .yandex) ? .cancel : .confirm) {
                    viewModel.gptAPI = api
                    viewModel.messages = []
                } label: {
                    HStack {
                        Text(api.rawValue)
                        if api == viewModel.gptAPI {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .padding(.leading, 2)
                        }
                    }
                }
            }
        }
    }

    private var clearChat: some View {
        Button {
            viewModel.clearChat()
        } label: {
            HStack {
                Text("Сбросить")
            }
        }
        .padding()
    }

    private var strategyButton: some View {
        Button {
            viewModel.isActiveStrategyDialog = true
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.contextStrategy.label).font(.caption)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 8)
        }
        .popover(isPresented: $viewModel.isActiveStrategyDialog, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ContextStrategy.allCases, id: \.self) { strategy in
                    Button {
                        viewModel.contextStrategy = strategy
                        viewModel.isActiveStrategyDialog = false
                    } label: {
                        HStack {
                            Text(strategy.label)
                            Spacer()
                            if strategy == viewModel.contextStrategy {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain) // Убираем дефолтную обводку кнопки на Mac
                    Divider().opacity(0.5)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 200) // На Mac нужно явно задать ширину
        }
    }


    private var gigaChatModelButton: some View {
        Button {
            viewModel.isActiveModelDialog = true
        } label: {
            HStack {
                Text(viewModel.gigaChatModel.rawValue)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .confirmationDialog("Выберите модель GigaChat", isPresented: $viewModel.isActiveModelDialog) {
            ForEach(GigaChatModel.allCases, id: \.self) { model in
                Button {
                    viewModel.gigaChatModel = model
                } label: {
                    HStack {
                        Text(model.rawValue)
                        if model == viewModel.gigaChatModel {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
    }
}
