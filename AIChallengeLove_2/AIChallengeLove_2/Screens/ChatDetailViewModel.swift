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

    let network: NetworkService
    private let messageStorage = MessageStorage()

    init(network: NetworkService) {
        self.network = network
        // Загружаем сохранённые сообщения и статистику при инициализации
        self.messages = messageStorage.loadMessages()
        self.info = messageStorage.loadInfo()
    }

    // MARK: - Public

    func sendMessage() {
        guard !inputText.isEmpty else { return }

        let newMessage = Message(role: .user, content: inputText)
        messages.append(newMessage)

        let messagesToSend = prepareMessagesForAPI()

        sendMessages(messagesToSend) { [weak self] responseMessage in
            guard let self else { return }
            messages.append(responseMessage)
            messageStorage.saveMessages(messages)
        }

        inputText = "" // очищаем поле ввода
    }

    func clearChat() {
        messages.removeAll()
        messageStorage.clearMessages()
    }
    
    func clearSessionStats() {
        info.session[gptAPI] = SessionGPT(input: 0, output: 0, total: 0)
        messageStorage.saveInfo(info)
    }

    // MARK: - Private

    private func prepareMessagesForAPI() -> [Message] {
        var processedMessages = messages

        if isStrictMode {
            // 1. Добавляем явное описание формата (JSON или список)
            // 2. Добавляем условие завершения (стоп-фраза "КОНЕЦ")
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
