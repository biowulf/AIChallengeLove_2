//
//  ChatDetailViewModel.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/15/25.
//

import Observation
import Alamofire
import Foundation
import SwiftUI

@Observable
final class ChatDetailViewModel {
    var inputText = ""
    var messages: [Message] = []
    var isLoading = false
    var isActiveDialog = false
    var gptAPI: GPTAPI = .gigachat
    var gigaChatModel: GigaChatModel = .chat2
    var isActiveModelDialog = false
    var isShowInfo: Bool = true
    var isShowBranches: Bool = false
    var info: Info = .init()
    var isActiveStrategyDialog = false
    var isStrictMode = false
    var maxTokensText: String = ""
    var temperature: Double = 0

    // Streaming properties
    var isStreaming = false
    var streamingText = ""
    var isStreamingComplete = false
    var useStreaming = false

    // Error state
    var lastRequestFailed = false

    // Context strategy
    var contextStrategy: ContextStrategy = .none {
        didSet { messageStorage.saveContextStrategy(contextStrategy) }
    }

    // Sliding Window: настраиваемый размер окна
    var contextWindowSize: Int = 10 {
        didSet {
            messageStorage.saveWindowSize(contextWindowSize)
            memoryManager?.updateWindowSize(contextWindowSize)
        }
    }
    var windowSizeText: String = "10"

    // GPT Summary (бывший .gpt)
    var summaries: [ConversationSummary] = []
    var isSummarizing = false
    @ObservationIgnored
    var summarizedUpToIndex: Int = 0
    private let summarizationBlockSize = 10

    // Sticky Facts
    var facts: [StickyFact] = []
    var isExtractingFacts = false

    // Branching (legacy)
    var checkpoints: [Checkpoint] = []
    var branches: [Branch] = []
    var activeBranchId: UUID? = nil {
        didSet { messageStorage.saveActiveBranchId(activeBranchId) }
    }

    // Dialog Lines (auto-branching)
    var dialogLines: [DialogLine] = []
    var activeLineId: UUID? = nil {
        didSet { messageStorage.saveActiveLineId(activeLineId) }
    }
    var isClassifying = false

    // Memory Layers
    var memoryManager: MemoryManager?
    var isExtractingWorkingMemory = false
    var isExtractingLongTermMemory = false
    var isShowMemoryPanel = false

    // System Prompt (unified profile + invariants)
    var isShowSystemPromptPanel = false

    // MCP
    var isShowMCPPanel = false
    var mcpManager = MCPManager()

    // Task State
    var isShowTaskPanel = false
    var taskTransitionError: String? = nil
    /// Если true — переходы между стадиями выполняются автоматически при обнаружении маркера AI
    var isAutoTransition = false
    /// Реактивное зеркало taskState из MemoryManager — обновляется через setTaskState()
    var taskState: TaskState = TaskState()
    /// Если true — первое сообщение в чате запускает стадийный поток (Research → ...)
    var isTaskModeEnabled: Bool = false

    let network: NetworkService
    private let messageStorage = MessageStorage()

    /// ID первого сообщения текущей стадии задачи.
    /// Все сообщения начиная с этого ID включаются в API-запрос (stage isolation).
    @ObservationIgnored
    private var taskStageFirstMessageId: UUID? = nil

    init(network: NetworkService) {
        self.network = network
        self.messages = messageStorage.loadMessages()
        self.info = messageStorage.loadInfo()
        self.summaries = messageStorage.loadSummaries()
        self.contextStrategy = messageStorage.loadContextStrategy()
        self.contextWindowSize = messageStorage.loadWindowSize()
        self.windowSizeText = "\(messageStorage.loadWindowSize())"
        self.facts = messageStorage.loadFacts()
        self.checkpoints = messageStorage.loadCheckpoints()
        self.branches = messageStorage.loadBranches()
        self.activeBranchId = messageStorage.loadActiveBranchId()
        self.dialogLines = messageStorage.loadDialogLines()
        self.activeLineId = messageStorage.loadActiveLineId()
        self.summarizedUpToIndex = min(
            summaries.reduce(0) { $0 + $1.originalMessageCount },
            messages.count
        )

        // Инициализация MemoryManager (всегда, чтобы долговременная память накапливалась)
        self.memoryManager = MemoryManager(
            storage: messageStorage,
            windowSize: self.contextWindowSize
        )
        // Инициализируем реактивное зеркало taskState из сохранённого состояния
        self.taskState = self.memoryManager?.taskState ?? TaskState()
    }

    // MARK: - Public

    /// Возвращает сообщения для отображения в UI.
    /// Скрывает isStageContext (служебный контекст стадии) — он уходит в API, но не показывается пользователю.
    func effectiveMessages() -> [Message] {
        return messages.filter { !$0.isStageContext }
    }

    /// Возвращает сообщения активной линии диалога (для контекста AI)
    func activeLineMessages() -> [Message] {
        guard contextStrategy == .branching,
              let lineId = activeLineId,
              let line = dialogLines.first(where: { $0.id == lineId }) else {
            return messages
        }
        return line.messages
    }

    func sendMessage() {
        guard !inputText.isEmpty else { return }

        // 1. Проверяем: есть ли pending transition и пользователь подтверждает/корректирует?
        if taskState.isActive, let pendingPhase = taskState.pendingTransition {
            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let confirmWords: Set<String> = ["ок", "ok", "да", "yes", "давай", "погнали",
                                             "подтверждаю", "вперёд", "вперед", "го", "go",
                                             "начнём", "начнем", "поехали", "да, переходим",
                                             "переходим", "принято"]
            if confirmWords.contains(trimmed) {
                // Пользователь подтвердил → выполняем переход
                inputText = ""
                transitionTask(to: pendingPhase)
                return
            } else {
                // Пользователь дал корректировку → сбрасываем pending, отправляем на AI
                clearPendingTransition()
                // Fall through: сообщение уйдёт в текущую стадию как корректировка
            }
        }

        // 2. Task mode: первое сообщение становится описанием задачи и запускает Research
        if isTaskModeEnabled && taskState.isEmpty {
            let description = inputText
            inputText = ""
            startTaskFromMessage(description)
            return
        }

        // 3. Обычная отправка
        let newMessage = Message(role: .user, content: inputText)
        inputText = ""

        if contextStrategy == .branching {
            // Для авто-ветвления: сначала добавляем в общий массив, затем классифицируем
            messages.append(newMessage)
            messageStorage.saveMessages(messages)
            classifyAndSend(userMessage: newMessage)
        } else {
            appendMessage(newMessage)
            performSend()
        }
    }

    func retryLastMessage() {
        lastRequestFailed = false
        performSend()
    }

    private func performSend() {
        lastRequestFailed = false

        // Проверяем, нужна ли суммаризация перед отправкой (GPT Summary)
        if contextStrategy == .gptSummary {
            let unsummarizedCount = messages.count - summarizedUpToIndex
            if unsummarizedCount > contextWindowSize {
                let block = getNextSummarizationBlock()
                if !block.isEmpty {
                    summarizeAndThenSend(block: block)
                    return
                }
            }
        }

        // Для Sticky Facts: извлекаем факты перед отправкой
        if contextStrategy == .stickyFacts {
            extractFactsAndThenSend()
            return
        }

        // Memory Layers: извлекаем рабочую и (периодически) долговременную память
        if contextStrategy == .memoryLayers {
            extractMemoriesAndThenSend()
            return
        }

        // Все остальные стратегии — отправляем напрямую
        let messagesToSend = prepareMessagesForAPI()
        sendMessages(messagesToSend) { [weak self] responseMessage in
            guard let self else { return }
            appendMessage(responseMessage)
            persistCurrentMessages()
            detectTaskMarkers(in: responseMessage.content)
        }
    }

    func clearChat() {
        messages.removeAll()
        summaries.removeAll()
        summarizedUpToIndex = 0
        facts.removeAll()
        checkpoints.removeAll()
        branches.removeAll()
        activeBranchId = nil
        dialogLines.removeAll()
        activeLineId = nil
        taskTransitionError = nil
        memoryManager?.clearConversationMemory() // Очищаем рабочую + задачу, долговременная память и system prompt остаются
        taskState = TaskState() // Сбрасываем реактивное зеркало
        taskStageFirstMessageId = nil
        messageStorage.clearMessages()
    }

    func clearLongTermMemory() {
        memoryManager?.clearLongTermMemory()
    }

    // MARK: - System Prompt Config

    func updateSystemPromptConfig(_ config: SystemPromptConfig) {
        memoryManager?.updateSystemPromptConfig(config)
    }

    // MARK: - Task State Controls

    /// Синхронно обновляет taskState в реактивном свойстве ViewModel и в MemoryManager.
    /// Используй только этот метод для изменения состояния задачи.
    private func setTaskState(_ state: TaskState) {
        taskState = state
        memoryManager?.updateTaskState(state)
    }

    func transitionTask(to phase: TaskPhase) {
        let fromPhase = taskState.currentPhase
        var state = taskState
        let result = TaskStateMachine.tryTransition(from: fromPhase, to: phase, state: &state)
        switch result {
        case .success:
            setTaskState(state)
            taskTransitionError = nil
            appendTransitionMessage(from: fromPhase, to: phase)
            // Передаём результат предыдущей стадии как контекст следующей
            autoSendStageResult(from: fromPhase)
        case .failure(let error):
            taskTransitionError = error.localizedDescription
        }
    }

    func resetTask() {
        let fromPhase = taskState.currentPhase
        setTaskState(TaskState())
        taskStageFirstMessageId = nil
        taskTransitionError = nil
        if fromPhase != .idle {
            appendTransitionMessage(from: fromPhase, to: .idle, reason: "Сброс задачи")
        }
    }

    /// Сбрасывает pendingTransition (пользователь отклонил предложение AI)
    func clearPendingTransition() {
        var state = taskState
        state.pendingTransition = nil
        setTaskState(state)
        taskTransitionError = nil
    }

    /// Запускает задачу из первого сообщения чата — устанавливает описание и переводит в Research
    private func startTaskFromMessage(_ description: String) {
        var state = taskState
        state.taskDescription = description
        let result = TaskStateMachine.tryTransition(from: state.currentPhase, to: .research, state: &state)
        switch result {
        case .success:
            setTaskState(state)
            taskTransitionError = nil
            appendTransitionMessage(from: .idle, to: .research)
            // Добавляем задачу как сообщение пользователя и отправляем AI
            let userMessage = Message(role: .user, content: description)
            taskStageFirstMessageId = userMessage.id   // Research начинается с этого сообщения
            appendMessage(userMessage)
            performSend()
        case .failure(let error):
            taskTransitionError = error.localizedDescription
        }
    }

    /// Передаёт последний ответ AI как контекст первого сообщения следующей стадии.
    /// Сообщение помечается isStageContext=true — скрыто в UI, но включено в API.
    private func autoSendStageResult(from fromPhase: TaskPhase) {
        let lastAssistantContent = messages
            .filter { $0.role == .assistant && !$0.isTransitionMarker }
            .last?.content ?? ""
        guard !lastAssistantContent.isEmpty else { return }

        let stageResultMessage = Message(
            role: .user,
            content: "Контекст из стадии \(fromPhase.emoji) \(fromPhase.label):\n\n\(lastAssistantContent)",
            isStageContext: true   // скрыто в чате, видно только в API
        )
        taskStageFirstMessageId = stageResultMessage.id  // новая стадия начинается здесь
        appendMessage(stageResultMessage)
        performSend()
    }

    // MARK: - Transition Message

    /// Добавляет информационное сообщение о смене стадии — только для UI, не отправляется в AI
    private func appendTransitionMessage(from: TaskPhase, to: TaskPhase, reason: String = "") {
        let reasonSuffix = reason.isEmpty ? "" : " (\(reason))"
        let content = "⟶ Стадия: \(from.emoji) \(from.label) → \(to.emoji) \(to.label)\(reasonSuffix)"
        let markerMessage = Message(
            role: .system,
            content: content,
            isTransitionMarker: true
        )
        appendMessage(markerMessage)
    }

    func clearSessionStats() {
        info.session[gptAPI] = SessionGPT(input: 0, output: 0, total: 0)
        messageStorage.saveInfo(info)
    }

    func clearFacts() {
        facts.removeAll()
        messageStorage.saveFacts(facts)
    }

    // MARK: - Branching

    func createCheckpoint(name: String? = nil) {
        let checkpointName = name ?? "Чекпоинт \(checkpoints.count + 1)"

        // Если мы в ветке, «коммитим» её сообщения в основной массив
        if let branchId = activeBranchId,
           let branch = branches.first(where: { $0.id == branchId }),
           let checkpoint = checkpoints.first(where: { $0.id == branch.checkpointId }) {
            let baseMessages = Array(messages.prefix(checkpoint.messageCount))
            messages = baseMessages + branch.messages
            messageStorage.saveMessages(messages)
            activeBranchId = nil
        }

        let cp = Checkpoint(name: checkpointName, messageCount: messages.count)
        checkpoints.append(cp)
        messageStorage.saveCheckpoints(checkpoints)
    }

    func createBranch(from checkpointId: UUID, name: String? = nil) {
        let branchName = name ?? "Ветка \(branches.filter { $0.checkpointId == checkpointId }.count + 1)"
        let branch = Branch(checkpointId: checkpointId, name: branchName)
        branches.append(branch)
        activeBranchId = branch.id
        messageStorage.saveBranches(branches)
    }

    func switchToBranch(_ branchId: UUID) {
        activeBranchId = branchId
    }

    func switchToMainTimeline() {
        activeBranchId = nil
    }

    func branchesByCheckpoint() -> [(checkpoint: Checkpoint, branches: [Branch])] {
        checkpoints.map { cp in
            (checkpoint: cp, branches: branches.filter { $0.checkpointId == cp.id })
        }
    }

    // MARK: - Dialog Lines (Auto-branching)

    func switchToLine(_ lineId: UUID) {
        activeLineId = lineId
    }

    /// Определяет линию для сообщения и отправляет
    private func classifyAndSend(userMessage: Message) {
        // Если линий ещё нет — создаём первую без классификации
        if dialogLines.isEmpty {
            createFirstLineAndSend(userMessage: userMessage)
            return
        }

        isClassifying = true
        withAnimation { isLoading = true }

        let classificationMessages = [
            Message(role: .system, content: buildClassificationPrompt()),
            Message(role: .user, content: userMessage.content)
        ]

        sendAuxiliaryRequest(classificationMessages) { [weak self] responseText in
            guard let self else { return }
            isClassifying = false

            let classification = parseClassification(responseText)

            switch classification {
            case .existingLine(let lineId):
                activeLineId = lineId
                appendToActiveLine(userMessage)
            case .newLine(let topic):
                let newLine = DialogLine(topic: topic, messages: [userMessage])
                dialogLines.append(newLine)
                activeLineId = newLine.id
                messageStorage.saveDialogLines(dialogLines)
            }

            // Теперь отправляем основной запрос с контекстом линии
            let messagesToSend = prepareMessagesForAPI()
            sendMessages(messagesToSend) { [weak self] responseMessage in
                guard let self else { return }
                // Добавляем ответ в общий массив и в активную линию
                appendMessage(responseMessage)
                appendToActiveLine(responseMessage)
            }
        }
    }

    private func createFirstLineAndSend(userMessage: Message) {
        withAnimation { isLoading = true }

        // Определяем тему по первому сообщению
        let topicMessages = [
            Message(role: .system, content: """
                Определи краткую тему (2-5 слов) для следующего сообщения пользователя. \
                Ответь ТОЛЬКО названием темы, без кавычек и пояснений.
                """),
            Message(role: .user, content: userMessage.content)
        ]

        sendAuxiliaryRequest(topicMessages) { [weak self] topicText in
            guard let self else { return }

            let topic = topicText.trimmingCharacters(in: .whitespacesAndNewlines)
            let line = DialogLine(
                topic: topic.isEmpty ? "Тема 1" : topic,
                messages: [userMessage]
            )
            dialogLines.append(line)
            activeLineId = line.id
            messageStorage.saveDialogLines(dialogLines)

            let messagesToSend = prepareMessagesForAPI()
            sendMessages(messagesToSend) { [weak self] responseMessage in
                guard let self else { return }
                appendMessage(responseMessage)
                appendToActiveLine(responseMessage)
            }
        }
    }

    private func buildClassificationPrompt() -> String {
        let linesDescription = dialogLines
            .enumerated()
            .map { "- id: \"\($1.id.uuidString)\", тема: \"\($1.topic)\" (\($1.messages.count) сообщ.)" }
            .joined(separator: "\n")

        return """
            Ты — классификатор тем диалога. Определи, к какой линии диалога относится \
            новое сообщение пользователя.

            Текущие линии диалога:
            \(linesDescription)

            Правила:
            1. Если сообщение продолжает или возвращается к существующей теме — верни её id.
            2. Если это новая тема — придумай краткое название (2-5 слов).
            3. Если пользователь просто делает пометку о будущей теме, но не переходит к ней — \
               верни id текущей активной линии.

            Активная линия сейчас: \(activeLineId?.uuidString ?? "нет")

            Ответь строго в формате JSON (без markdown):
            Для существующей темы: {"lineId": "uuid-строка"}
            Для новой темы: {"newTopic": "название темы"}
            """
    }

    private enum ClassificationResult {
        case existingLine(UUID)
        case newLine(String)
    }

    private func parseClassification(_ json: String) -> ClassificationResult {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8) else {
            return .newLine("Новая тема")
        }

        struct LineIdResponse: Decodable { let lineId: String? }
        struct NewTopicResponse: Decodable { let newTopic: String? }

        if let response = try? JSONDecoder().decode(LineIdResponse.self, from: data),
           let lineIdStr = response.lineId,
           let lineId = UUID(uuidString: lineIdStr),
           dialogLines.contains(where: { $0.id == lineId }) {
            return .existingLine(lineId)
        }

        if let response = try? JSONDecoder().decode(NewTopicResponse.self, from: data),
           let topic = response.newTopic, !topic.isEmpty {
            return .newLine(topic)
        }

        // Fallback: если не удалось распарсить, остаёмся на текущей линии
        if let currentId = activeLineId {
            return .existingLine(currentId)
        }
        return .newLine("Новая тема")
    }

    // MARK: - Private: Message routing

    private func appendMessage(_ message: Message) {
        messages.append(message)
        messageStorage.saveMessages(messages)
    }

    /// Добавляет сообщение в активную линию диалога
    private func appendToActiveLine(_ message: Message) {
        guard let lineId = activeLineId,
              let index = dialogLines.firstIndex(where: { $0.id == lineId }) else { return }
        dialogLines[index].messages.append(message)
        messageStorage.saveDialogLines(dialogLines)
    }

    private func persistCurrentMessages() {
        messageStorage.saveMessages(messages)
        if contextStrategy == .branching {
            messageStorage.saveDialogLines(dialogLines)
        }
    }

    // MARK: - Prepare messages for API

    private func prepareMessagesForAPI() -> [Message] {
        var processedMessages: [Message]

        // Stage isolation: если активна задача, берём только сообщения текущей стадии.
        // Иначе — вся история (без маркеров и stage-context сообщений).
        let allMessages: [Message]
        if taskState.isActive,
           let firstId = taskStageFirstMessageId,
           let startIdx = messages.firstIndex(where: { $0.id == firstId }) {
            // Текущая стадия: от stage-context-сообщения до конца, без transition-маркеров
            allMessages = Array(messages[startIdx...]).filter { !$0.isTransitionMarker }
        } else {
            // Обычный режим: вся история без маркеров и без скрытых stage-context сообщений
            allMessages = messages.filter { !$0.isTransitionMarker && !$0.isStageContext }
        }

        switch contextStrategy {
        case .none:
            processedMessages = allMessages

        case .slidingWindow:
            var startIndex = max(0, allMessages.count - contextWindowSize)
            while startIndex < allMessages.count &&
                  allMessages[startIndex].role != .user &&
                  allMessages[startIndex].role != .system {
                startIndex += 1
            }
            if startIndex < allMessages.count {
                processedMessages = Array(allMessages[startIndex...])
            } else {
                processedMessages = allMessages
            }

        case .gptSummary:
            var contextMessages: [Message] = []
            if !summaries.isEmpty {
                let combinedSummary = summaries
                    .enumerated()
                    .map { "Контекст беседы (часть \($0.offset + 1)): \($0.element.content)" }
                    .joined(separator: "\n\n")
                contextMessages.append(Message(
                    role: .system,
                    content: "Ниже приведено краткое содержание предыдущей части беседы. " +
                             "Используй его как контекст для ответов.\n\n\(combinedSummary)"
                ))
            }
            let safeIndex = min(summarizedUpToIndex, messages.count)
            let recentMessages = Array(messages[safeIndex...])
            contextMessages.append(contentsOf: recentMessages)
            processedMessages = contextMessages

        case .stickyFacts:
            var contextMessages: [Message] = []
            if !facts.isEmpty {
                let factsText = facts
                    .map { "- \($0.key): \($0.value)" }
                    .joined(separator: "\n")
                contextMessages.append(Message(
                    role: .system,
                    content: "Ключевые факты из диалога (используй как контекст):\n\(factsText)"
                ))
            }
            var startIndex = max(0, allMessages.count - contextWindowSize)
            while startIndex < allMessages.count &&
                  allMessages[startIndex].role != .user &&
                  allMessages[startIndex].role != .system {
                startIndex += 1
            }
            if startIndex < allMessages.count {
                contextMessages.append(contentsOf: Array(allMessages[startIndex...]))
            } else {
                contextMessages.append(contentsOf: allMessages)
            }
            processedMessages = contextMessages

        case .branching:
            // Для авто-ветвления: используем сообщения активной линии
            let lineMessages = activeLineMessages()
            if let lineId = activeLineId,
               let line = dialogLines.first(where: { $0.id == lineId }) {
                var contextMessages: [Message] = []
                contextMessages.append(Message(
                    role: .system,
                    content: "Текущая тема обсуждения: \(line.topic). Отвечай в контексте этой темы."
                ))
                contextMessages.append(contentsOf: lineMessages)
                processedMessages = contextMessages
            } else {
                processedMessages = allMessages
            }

        case .memoryLayers:
            // Слои памяти: MemoryManager собирает контекст из всех слоёв (включая профиль, инварианты, задачу)
            if let mm = memoryManager {
                processedMessages = mm.composeMessagesForAPI(allMessages: allMessages)
            } else {
                // Fallback: sliding window
                processedMessages = Array(allMessages.suffix(contextWindowSize))
            }
        }

        // Инъекция system prompt + состояния задачи для ВСЕХ стратегий кроме memoryLayers
        // (memoryLayers уже обрабатывает их в composeMessagesForAPI)
        if contextStrategy != .memoryLayers, let mm = memoryManager {
            var injectionParts: [String] = []

            if mm.systemPromptConfig.isActive, !mm.systemPromptConfig.isEmpty {
                injectionParts.append(mm.systemPromptConfig.customSystemPrompt)
            }

            if taskState.isActive {
                injectionParts.append(taskState.asSystemPromptText())
            }

            if !injectionParts.isEmpty {
                let injectionText = injectionParts.joined(separator: "\n\n---\n\n")
                if let firstSystemIdx = processedMessages.firstIndex(where: { $0.role == .system }) {
                    let existing = processedMessages[firstSystemIdx]
                    processedMessages[firstSystemIdx] = Message(
                        role: .system,
                        content: injectionText + "\n\n---\n\n" + existing.content
                    )
                } else {
                    processedMessages.insert(Message(role: .system, content: injectionText), at: 0)
                }
            }
        }

        if isStrictMode {
            let strictText = """
                ОТВЕЧАЙ СТРОГО ПО ФОРМАТУ:
                1. Краткий ответ (до 10 слов на весь ответ).
                2. В конце обязательно пиши слово 'КОНЕЦ' если ты уложился в ограничение ответа.
                3. после слова СТОП ты должен перестать отвечать если не закончил.
                Используй только маркированные списки.
                """

            if let firstIndex = processedMessages.firstIndex(where: { $0.role == .system }) {
                // Объединяем с существующим system message
                let existing = processedMessages[firstIndex]
                processedMessages[firstIndex] = Message(
                    role: .system,
                    content: existing.content + "\n\n---\n\n" + strictText
                )
            } else {
                processedMessages.insert(Message(role: .system, content: strictText), at: 0)
            }
        }

        return processedMessages
    }

    // MARK: - GPT Summarization

    private func getNextSummarizationBlock() -> [Message] {
        let unsummarizedMessages = Array(messages[summarizedUpToIndex...])
        let eligibleCount = unsummarizedMessages.count - contextWindowSize
        guard eligibleCount > 0 else { return [] }

        let blockSize = min(eligibleCount, summarizationBlockSize)
        let startIdx = summarizedUpToIndex
        let endIdx = startIdx + blockSize
        return Array(messages[startIdx..<endIdx])
    }

    private func summarizeAndThenSend(block: [Message]) {
        isSummarizing = true
        withAnimation { isLoading = true }

        let summaryMessages = [
            Message(role: .system, content: buildSummarizationPrompt())
        ] + block

        sendAuxiliaryRequest(summaryMessages) { [weak self] summaryText in
            guard let self else { return }

            if !summaryText.isEmpty {
                let summary = ConversationSummary(
                    content: summaryText,
                    originalMessageCount: block.count,
                    createdAt: Date()
                )
                summaries.append(summary)
                summarizedUpToIndex += block.count
                messageStorage.saveSummaries(summaries)
            }

            isSummarizing = false

            let messagesToSend = prepareMessagesForAPI()
            sendMessages(messagesToSend) { [weak self] responseMessage in
                guard let self else { return }
                appendMessage(responseMessage)
                persistCurrentMessages()
            }
        }
    }

    private func buildSummarizationPrompt() -> String {
        return """
        Ты — помощник для сжатия контекста диалога. \
        Твоя задача: кратко пересказать содержание переписки между пользователем и ассистентом. \
        Сохрани ключевые факты, решения, имена, числа и важные детали. \
        Опусти приветствия, повторы и несущественные фразы. \
        Ответ дай одним абзацем, не более 150 слов. \
        Пиши на том же языке, на котором велась беседа.
        """
    }

    // MARK: - Sticky Facts

    private func extractFactsAndThenSend() {
        isExtractingFacts = true
        withAnimation { isLoading = true }

        let recentMessages = Array(effectiveMessages().filter { !$0.isTransitionMarker }.suffix(4))
        let extractionMessages = [
            Message(role: .system, content: buildFactExtractionPrompt())
        ] + recentMessages

        sendAuxiliaryRequest(extractionMessages) { [weak self] extractedJSON in
            guard let self else { return }
            isExtractingFacts = false

            if let newFacts = parseExtractedFacts(extractedJSON) {
                mergeFacts(newFacts)
                messageStorage.saveFacts(facts)
            }

            let messagesToSend = prepareMessagesForAPI()
            sendMessages(messagesToSend) { [weak self] responseMessage in
                guard let self else { return }
                appendMessage(responseMessage)
                persistCurrentMessages()
            }
        }
    }

    private func buildFactExtractionPrompt() -> String {
        return """
        Ты — помощник для извлечения ключевых фактов из диалога. \
        Проанализируй последние сообщения и извлеки важные факты: цели, ограничения, \
        предпочтения, решения, договорённости, имена, даты, числа. \
        Ответ дай строго в формате JSON массива: \
        [{"key": "название факта", "value": "значение"}] \
        Если новых фактов нет, верни пустой массив []. \
        Если факт обновляет старый — используй тот же ключ с новым значением. \
        Пиши на том же языке, на котором велась беседа. \
        Максимум 10 фактов.
        """
    }

    private func parseExtractedFacts(_ json: String) -> [StickyFact]? {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8) else { return nil }
        struct RawFact: Decodable { let key: String; let value: String }
        guard let raw = try? JSONDecoder().decode([RawFact].self, from: data) else { return nil }
        return raw.map { StickyFact(key: $0.key, value: $0.value) }
    }

    private func mergeFacts(_ newFacts: [StickyFact]) {
        for newFact in newFacts {
            if let existingIndex = facts.firstIndex(where: { $0.key.lowercased() == newFact.key.lowercased() }) {
                facts[existingIndex] = newFact
            } else {
                facts.append(newFact)
            }
        }
    }

    // MARK: - Memory Layers Extraction

    private func extractMemoriesAndThenSend() {
        guard let mm = memoryManager else {
            // Fallback: отправляем без извлечения
            let messagesToSend = prepareMessagesForAPI()
            sendMessages(messagesToSend) { [weak self] responseMessage in
                guard let self else { return }
                appendMessage(responseMessage)
                persistCurrentMessages()
            }
            return
        }

        isExtractingWorkingMemory = true
        withAnimation { isLoading = true }

        // Шаг 1: Извлекаем рабочую память из последних 6 сообщений (без системных маркеров стадий)
        let recentForExtraction = Array(effectiveMessages().filter { !$0.isTransitionMarker }.suffix(6))
        let workingMemoryMessages = [
            Message(role: .system, content: mm.buildWorkingMemoryExtractionPrompt())
        ] + recentForExtraction

        sendAuxiliaryRequest(workingMemoryMessages) { [weak self] responseText in
            guard let self, let mm = self.memoryManager else { return }
            self.isExtractingWorkingMemory = false

            if let newWorkingMemory = mm.parseWorkingMemoryResponse(responseText) {
                mm.updateWorkingMemory(newWorkingMemory)
            }

            // Шаг 2: Периодически извлекаем долговременную память (каждые 5 обменов)
            if mm.shouldExtractLongTermMemory() {
                self.extractLongTermMemoryAndThen(mm: mm) {
                    self.sendWithMemoryLayers()
                }
            } else {
                self.sendWithMemoryLayers()
            }
        }
    }

    private func extractLongTermMemoryAndThen(mm: MemoryManager, completion: @escaping () -> Void) {
        isExtractingLongTermMemory = true

        let existingMemoryText = mm.longTermMemory.asSystemPromptText()
        let recentForLongTerm = Array(effectiveMessages().filter { !$0.isTransitionMarker }.suffix(10))
        let longTermMessages = [
            Message(role: .system, content: mm.buildLongTermMemoryExtractionPrompt(
                existingMemory: existingMemoryText
            ))
        ] + recentForLongTerm

        sendAuxiliaryRequest(longTermMessages) { [weak self] responseText in
            guard let self, let mm = self.memoryManager else { return }
            self.isExtractingLongTermMemory = false

            if let newEntries = mm.parseLongTermMemoryResponse(responseText), !newEntries.isEmpty {
                mm.updateLongTermMemory(with: newEntries)
            }
            mm.resetLongTermExtractionCounter()

            completion()
        }
    }

    private func sendWithMemoryLayers() {
        let messagesToSend = prepareMessagesForAPI()
        sendMessages(messagesToSend) { [weak self] responseMessage in
            guard let self else { return }
            appendMessage(responseMessage)
            persistCurrentMessages()
            detectTaskMarkers(in: responseMessage.content)
        }
    }

    // MARK: - Task Marker Detection

    /// Детектирует маркеры стадий в ответе AI.
    /// В авто-режиме — сразу выполняет переход.
    /// В ручном режиме — устанавливает pendingTransition для подтверждения пользователем.
    private func detectTaskMarkers(in text: String) {
        guard taskState.isActive else { return }

        let uppercased = text.uppercased()
        let current = taskState.currentPhase

        // Определяем целевую стадию по маркеру
        var targetPhase: TaskPhase?

        switch current {
        case .research:
            if uppercased.contains("ИССЛЕДОВАНИЕ ЗАВЕРШЕНО") {
                targetPhase = .plan
            }
        case .plan:
            if uppercased.contains("ПЛАН ГОТОВ") {
                targetPhase = .executing
            }
        case .executing:
            if uppercased.contains("ВЫПОЛНЕНИЕ ЗАВЕРШЕНО") {
                targetPhase = .validation
            } else if uppercased.contains("НУЖНО ПЕРЕИССЛЕДОВАНИЕ") {
                targetPhase = .research
            }
        case .validation:
            if uppercased.contains("ПРОВЕРКА ПРОЙДЕНА") {
                targetPhase = .done           // Validation → Done напрямую
            } else if uppercased.contains("НУЖНЫ ДОРАБОТКИ") {
                targetPhase = .executing
            } else if uppercased.contains("НУЖНО ПЕРЕИССЛЕДОВАНИЕ") {
                targetPhase = .research
            }
        case .report:
            if uppercased.contains("ОТЧЁТ ГОТОВ") {
                targetPhase = .done
            }
        default:
            break
        }

        guard let target = targetPhase else { return }

        if isAutoTransition {
            // Авто-режим: выполняем переход сразу
            transitionTask(to: target)
        } else {
            // Ручной режим: устанавливаем pending + показываем запрос подтверждения в чате
            var state = taskState
            state.pendingTransition = target
            setTaskState(state)
            appendConfirmationRequest(from: current, to: target)
        }
    }

    /// Добавляет сообщение-запрос подтверждения в чат (не отправляется в AI)
    private func appendConfirmationRequest(from fromPhase: TaskPhase, to toPhase: TaskPhase) {
        let content = """
            💬 AI предлагает: \(fromPhase.emoji) \(fromPhase.label) → \(toPhase.emoji) \(toPhase.label)
            Напишите «ок», «давай» или «погнали» для перехода — или опишите что нужно исправить.
            """
        let msg = Message(role: .system, content: content, isTransitionMarker: true)
        appendMessage(msg)
    }

    // MARK: - Auxiliary LLM request (summarization / fact extraction)

    private func sendAuxiliaryRequest(_ messages: [Message], completion: @escaping (String) -> Void) {
        switch gptAPI {
        case .gigachat:
            network.fetch(for: messages,
                         model: gigaChatModel,
                         maxTokens: 500,
                         temperature: 0) { result in
                switch result {
                case .success(let payload):
                    completion(payload.choices.first?.message.content ?? "")
                case .failure(let error):
                    print("Ошибка вспомогательного запроса: \(error.localizedDescription)")
                    completion("")
                }
            }
        case .yandex:
            network.fetchYA(for: messages,
                           maxTokens: 500,
                           temperature: 0) { result in
                switch result {
                case .success(let payload):
                    completion(payload.result.alternatives.first?.message.text ?? "")
                case .failure(let error):
                    print("Ошибка вспомогательного запроса YA: \(error.localizedDescription)")
                    completion("")
                }
            }
        }
    }

    // MARK: - Send messages

    private func sendMessages(_ messages: [Message], completion: @escaping (Message) -> Void) {
        withAnimation {
            isLoading = true
        }

        let maxTokens = Int(maxTokensText)
        let temperature = Float(temperature)

        switch gptAPI {
        case .gigachat:
            if useStreaming {
                sendStreamingRequest(messages: messages,
                                   maxTokens: maxTokens,
                                   temperature: temperature,
                                   completion: completion)
            } else {
                sendNonStreamingRequest(messages: messages,
                                      maxTokens: maxTokens,
                                      temperature: temperature,
                                      completion: completion)
            }
        case .yandex:
            network.fetchYA(for: messages, maxTokens: maxTokens, temperature: temperature) { [weak self] result in
                guard let self else { return }
                isLoading = false
                switch result {
                case .success(let payload):
                    if let responseMessage = payload.result.alternatives.first?.message {
                        completion(.init(role: responseMessage.role, content: responseMessage.text))
                    }
                    let usage = payload.result.usage

                    var requestInfo = info.request[gptAPI] ?? .init(input: 0, output: 0, total: 0)
                    requestInfo.input = Int(usage.inputTextTokens) ?? 0
                    requestInfo.output = Int(usage.completionTokens) ?? 0
                    requestInfo.total = Int(usage.totalTokens) ?? 0
                    info.request[gptAPI] = requestInfo

                    var session = info.session[gptAPI] ?? .init(input: 0, output: 0, total: 0)
                    session.input += Int(usage.inputTextTokens) ?? 0
                    session.output += Int(usage.completionTokens) ?? 0
                    session.total += Int(usage.totalTokens) ?? 0
                    info.session[gptAPI] = session

                    var appSession = info.appSession[gptAPI] ?? .init(input: 0, output: 0, total: 0)
                    appSession.input += Int(usage.inputTextTokens) ?? 0
                    appSession.output += Int(usage.completionTokens) ?? 0
                    appSession.total += Int(usage.totalTokens) ?? 0
                    info.appSession[gptAPI] = appSession

                    messageStorage.saveInfo(info)
                case .failure(let error):
                    self.lastRequestFailed = true
                    print("Ошибка запроса: ", error.localizedDescription)
                }
            }
        }
    }

    private func sendStreamingRequest(messages: [Message],
                                     maxTokens: Int?,
                                     temperature: Float,
                                     completion: @escaping (Message) -> Void) {
        streamingText = ""
        isStreamingComplete = false
        isStreaming = true

        network.fetchStream(
            for: messages,
            model: gigaChatModel,
            maxTokens: maxTokens,
            temperature: temperature
        ) { [weak self] chunk in
            DispatchQueue.main.async {
                self?.streamingText += chunk
            }
        } onComplete: { [weak self] usage in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isStreaming = false
                self.isStreamingComplete = true
                self.isLoading = false

                let finalMessage = Message(role: .assistant, content: self.streamingText)
                completion(finalMessage)

                if let usage = usage {
                    self.updateUsageStats(usage: usage)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.streamingText = ""
                    self.isStreamingComplete = false
                }
            }
        } onError: { [weak self] error in
            DispatchQueue.main.async {
                self?.isStreaming = false
                self?.isLoading = false
                self?.streamingText = ""
                self?.lastRequestFailed = true
                print("Ошибка streaming запроса: ", error.localizedDescription)
            }
        }
    }

    private func sendNonStreamingRequest(messages: [Message],
                                        maxTokens: Int?,
                                        temperature: Float,
                                        completion: @escaping (Message) -> Void) {
        network.fetch(for: messages,
                     model: gigaChatModel,
                     maxTokens: maxTokens,
                     temperature: temperature) { [weak self] result in
            guard let self else { return }
            isLoading = false
            switch result {
            case .success(let payload):
                if let responseMessage = payload.choices.first?.message {
                    completion(responseMessage)
                }
                updateUsageStats(usage: payload.usage)
            case .failure(let error):
                lastRequestFailed = true
                print("Ошибка запроса: ", error.localizedDescription)
            }
        }
    }

    private func updateUsageStats(usage: Usage) {
        var requestInfo = info.request[gptAPI] ?? .init(input: 0, output: 0, total: 0)
        requestInfo.input = usage.promptTokens
        requestInfo.output = usage.completionTokens
        requestInfo.total = usage.totalTokens
        info.request[gptAPI] = requestInfo

        var session = info.session[gptAPI] ?? .init(input: 0, output: 0, total: 0)
        session.input += usage.promptTokens
        session.output += usage.completionTokens
        session.total += usage.totalTokens
        info.session[gptAPI] = session

        var appSession = info.appSession[gptAPI] ?? .init(input: 0, output: 0, total: 0)
        appSession.input += usage.promptTokens
        appSession.output += usage.completionTokens
        appSession.total += usage.totalTokens
        info.appSession[gptAPI] = appSession

        messageStorage.saveInfo(info)
    }
}
