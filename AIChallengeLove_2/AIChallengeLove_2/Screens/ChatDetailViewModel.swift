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
    var info: Info = .init()
    var isActiveCollapseDialog = false
    var isStrictMode = false
    var maxTokensText: String = ""
    var temperature: Double = 0

    // Streaming properties
    var isStreaming = false
    var streamingText = ""
    var isStreamingComplete = false
    var useStreaming = false // Переключатель для использования streaming

    // Context management
    var collapseType: CollapseType = .none {
        didSet { messageStorage.saveCollapseType(collapseType) }
    }
    var summaries: [ConversationSummary] = []
    var isSummarizing = false
    @ObservationIgnored
    var summarizedUpToIndex: Int = 0

    private let contextWindowSize = 10
    private let summarizationBlockSize = 10

    let network: NetworkService
    private let messageStorage = MessageStorage()

    init(network: NetworkService) {
        self.network = network
        // Загружаем сохранённые сообщения и статистику при инициализации
        self.messages = messageStorage.loadMessages()
        self.info = messageStorage.loadInfo()
        self.summaries = messageStorage.loadSummaries()
        self.collapseType = messageStorage.loadCollapseType()
        self.summarizedUpToIndex = min(
            summaries.reduce(0) { $0 + $1.originalMessageCount },
            messages.count
        )
    }

    // MARK: - Public

    func sendMessage() {
        guard !inputText.isEmpty else { return }

        let newMessage = Message(role: .user, content: inputText)
        messages.append(newMessage)
        inputText = ""

        // Проверяем, нужна ли суммаризация перед отправкой
        if collapseType == .gpt {
            let unsummarizedCount = messages.count - summarizedUpToIndex
            if unsummarizedCount > contextWindowSize {
                let block = getNextSummarizationBlock()
                if !block.isEmpty {
                    summarizeAndThenSend(block: block)
                    return
                }
            }
        }

        // Суммаризация не нужна — отправляем напрямую
        let messagesToSend = prepareMessagesForAPI()
        sendMessages(messagesToSend) { [weak self] responseMessage in
            guard let self else { return }
            messages.append(responseMessage)
            messageStorage.saveMessages(messages)
        }
    }

    func clearChat() {
        messages.removeAll()
        summaries.removeAll()
        summarizedUpToIndex = 0
        messageStorage.clearMessages()
    }
    
    func clearSessionStats() {
        info.session[gptAPI] = SessionGPT(input: 0, output: 0, total: 0)
        messageStorage.saveInfo(info)
    }

    // MARK: - Private

    private func prepareMessagesForAPI() -> [Message] {
        var processedMessages: [Message]

        switch collapseType {
        case .none:
            processedMessages = messages
        case .cut:
            // Обрезка: берём только последние N сообщений
            var startIndex = max(0, messages.count - contextWindowSize)
            // Гарантируем что первое отправляемое сообщение — user или system,
            // т.к. GigaChat/Yandex отклоняют контекст, начинающийся с assistant
            while startIndex < messages.count &&
                  messages[startIndex].role != .user &&
                  messages[startIndex].role != .system {
                startIndex += 1
            }
            processedMessages = Array(messages[startIndex...])

        case .gpt:
            // AI-резюме: [системное сообщение с резюме] + [несуммаризированные сообщения]
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
        }

        if isStrictMode {
            let instruction = Message(role: .system, content: """
                ОТВЕЧАЙ СТРОГО ПО ФОРМАТУ:
                1. Краткий ответ (до 10 слов на весь ответ).
                2. В конце обязательно пиши слово 'КОНЕЦ' если ты уложился в ограничение ответа.
                3. после слова СТОП ты должен перестать отвечать если не закончил.
                Используй только маркированные списки.
                """)
            processedMessages.insert(instruction, at: 0)
        }

        return processedMessages
    }

//     MARK: - Summarization

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

        sendSummarizationRequest(summaryMessages) { [weak self] summaryText in
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
                print("Суммаризация завершена: \(block.count) сообщений -> резюме")
            } else {
                print("Суммаризация не удалась, отправляем без сжатия")
            }

            isSummarizing = false

            let messagesToSend = prepareMessagesForAPI()
            sendMessages(messagesToSend) { [weak self] responseMessage in
                guard let self else { return }
                messages.append(responseMessage)
                messageStorage.saveMessages(messages)
            }
        }
    }

    private func sendSummarizationRequest(_ messages: [Message], completion: @escaping (String) -> Void) {
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
                    print("Ошибка суммаризации: \(error.localizedDescription)")
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
                    print("Ошибка суммаризации YA: \(error.localizedDescription)")
                    completion("")
                }
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

    private func sendMessages(_ messages: [Message], completion: @escaping (Message) -> Void) {
        withAnimation {
            isLoading = true
        }

        let maxTokens = Int(maxTokensText)
        let temperature = Float(temperature)

        switch gptAPI {
        case .gigachat:
            // Используем streaming если включен флаг
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
                    print("Ошибка запроса: ", error.localizedDescription)
                }
            }
        }
    }
    
    private func sendStreamingRequest(messages: [Message], 
                                     maxTokens: Int?, 
                                     temperature: Float, 
                                     completion: @escaping (Message) -> Void) {
        // Сбрасываем состояние стрима
        streamingText = ""
        isStreamingComplete = false
        isStreaming = true
        
        network.fetchStream(
            for: messages,
            model: gigaChatModel,
            maxTokens: maxTokens,
            temperature: temperature
        ) { [weak self] chunk in
            // Получаем кусочек текста
            DispatchQueue.main.async {
                self?.streamingText += chunk
            }
        } onComplete: { [weak self] usage in
            // Стрим завершен
            guard let self else { return }
            
            DispatchQueue.main.async {
                self.isStreaming = false
                self.isStreamingComplete = true
                self.isLoading = false
                
                // Создаем финальное сообщение
                let finalMessage = Message(role: .assistant, content: self.streamingText)
                completion(finalMessage)
                
                // Обновляем статистику если есть usage
                if let usage = usage {
                    self.updateUsageStats(usage: usage)
                }
                
                // Сбрасываем streaming text для следующего запроса
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
