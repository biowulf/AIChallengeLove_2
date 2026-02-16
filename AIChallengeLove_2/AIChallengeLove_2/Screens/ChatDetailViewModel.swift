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
    var messages: [Message] = [] // Хранение сообщений
    var isLoading = false
    var isActiveDialog = false
    var gptAPI: GPTAPI = .gigachat
    var isShowInfo: Bool = true
    var info: Info = .init()
    var isActiveCollapseDialog = false

    let network: NetworkService

    init(network: NetworkService) {
        self.network = network
    }

    // MARK: - Public

    func sendMessage() {
        guard !inputText.isEmpty else { return }

        let newMessage = Message(role: .user, content: inputText)
        messages.append(newMessage)

        sendMessages(messages) { [weak self] responseMessage in
            guard let self else { return }
            messages.append(responseMessage)
        }

        inputText = "" // очищаем поле ввода
    }

    func clearChat() {
        messages.removeAll()
    }

    // MARK: - Private

    private func sendMessages(_ messages: [Message], completion: @escaping (Message) -> Void) {
        withAnimation {
            isLoading = true
        }

        switch gptAPI {
        case .gigachat:
            network.fetch(for: messages) { [weak self] result in
                guard let self else { return }
                isLoading = false
                switch result {
                case .success(let payload):
                    if let responseMessage = payload.choices.first?.message {
                        completion(responseMessage)
                    }
                    let usage = payload.usage

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
                case .failure(let error):
                    print("Ошибка запроса: ", error.localizedDescription)
                }
            }
        case .yandex:
            network.fetchYA(for: messages) { [weak self] result in
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
                case .failure(let error):
                    print("Ошибка запроса: ", error.localizedDescription)
                }
            }
        }
    }
}
