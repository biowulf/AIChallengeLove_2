//
//  Network.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/2/25.
//

import Alamofire
import SwiftData
import Foundation

enum NetworkError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case decodingFailed
}

class NetworkService {
    enum Format {
        case text
        case json
    }

    let session: Session

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init(session: Session) {
        self.session = session
    }

    func fetch(for newMessages: [Message],
               model: GigaChatModel = .chat2,
               format: Format = .text,
               maxTokens: Int? = nil,
               temperature: Float = 0,
               completion: @escaping (Result<ResponsePayload, AFError>) -> Void) {

        var messages: [Message] = newMessages
        if format == .json && newMessages.first?.role != .system {
            messages.insert(addJSONSystemPromt(), at: 0)
        }

        let dto = RequestModel(model: model,
                               messages: messages,
                               temperature: temperature,
                               maxTokens: maxTokens,
                               repetitionPenalty: 1,
                               updateInterval: 0,
                               functions: [],
                               stream: false)

        session.request("https://gigachat.devices.sberbank.ru/api/v1/chat/completions",
                        method: .post,
                        parameters: dto,
                        encoder: .json(encoder: encoder))
        .validate()
        .responseDecodable(of: ResponsePayload.self, decoder: decoder) { response in
            print(dump(response.result))
            completion(response.result)
        }

    }

    

    func fetchYA(for newMessages: [Message],
               format: Format = .text,
               maxTokens: Int? = nil,
               temperature: Float = 0,
               completion: @escaping (Result<YAResponse, AFError>) -> Void) {

        var messages: [Message] = newMessages
        if format == .json && newMessages.first?.role != .system {
            messages.insert(addJSONSystemPromt(), at: 0)
        }

        let dto = YARequestModel(completionOptions: .init(stream: false,
                                                          temperature: temperature,
                                                          maxTokens: maxTokens),
                                 messages: messages.compactMap({ .init(role: $0.role,
                                                                       text: $0.content) }))

        session.request("https://llm.api.cloud.yandex.net/foundationModels/v1/completion",
                        method: .post,
                        parameters: dto,
                        encoder: .json)
        .validate()
        .responseDecodable(of: YAResponse.self) { response in
            print(dump(response.result))
            completion(response.result)
        }

    }

    private func addJSONSystemPromt() -> Message {
        return
            .init(
                role: .system,
                content: "Ты можешь отвечать только валидным JSON формата {\n \"role\": \"[system, user, assistant, function]]\",\n \"content\": \"...\"\n}"
            )
    }
}


