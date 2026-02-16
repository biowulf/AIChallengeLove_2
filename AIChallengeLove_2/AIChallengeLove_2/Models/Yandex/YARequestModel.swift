//
//  YARequestModel.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/10/25.
//

nonisolated struct YARequestModel: Codable, Sendable {
    let modelUri: String = "gpt:///yandexgpt/rc"
    let completionOptions: CompletionOptions
    let messages: [YAMessage]
    let toolChoice = YAToolChoice(mode: "AUTO")
}

nonisolated struct CompletionOptions: Codable, Sendable {
    let stream: Bool
    let temperature: Float
    let maxTokens: Int
}

nonisolated struct YAMessage: Codable, Sendable {
    let role: Role
    let text: String
}

nonisolated struct YAToolChoice: Codable, Sendable {
    let mode: String
}
