//
//  RequestModel.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/3/25.
//

nonisolated struct RequestModel: Encodable, Sendable {
    let model: GigaChatModel
    let messages: [Message]
    let temperature: Float
    let maxTokens: Int?
    let repetitionPenalty: Float
    let updateInterval: Int
    let functionCall = "auto"
    let functions: [Function]
    let stream: Bool
}

nonisolated struct FunctionCall: Encodable, Sendable {
    let name: String
}

nonisolated struct Function: Encodable, Sendable {
    let name: String
    let description: String
//    let parameters: [String:Encodable]

}
