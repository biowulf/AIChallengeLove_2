//
//  RequestModel.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/3/25.
//

// ───────────────────────────────────────────────────────────
// MARK: - Request
// ───────────────────────────────────────────────────────────

nonisolated struct RequestModel: Encodable, Sendable {
    let model: GigaChatModel
    let messages: [APIMessage]
    let temperature: Float
    let maxTokens: Int?
    let repetitionPenalty: Float
    let updateInterval: Int
    /// "auto" — модель сама решает вызывать ли функцию; "none" — не вызывать.
    let functionCall: String
    let functions: [GigaFunction]
    let stream: Bool

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model,             forKey: .model)
        try c.encode(messages,          forKey: .messages)
        try c.encode(temperature,       forKey: .temperature)
        try c.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try c.encode(repetitionPenalty, forKey: .repetitionPenalty)
        try c.encode(updateInterval,    forKey: .updateInterval)
        try c.encode(stream,            forKey: .stream)
        // GigaChat возвращает 500 если передать functions: [] (пустой массив).
        // Отправляем function_call и functions только когда есть реальные функции.
        if !functions.isEmpty {
            try c.encode(functionCall, forKey: .functionCall)
            try c.encode(functions,    forKey: .functions)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature, maxTokens, repetitionPenalty,
             updateInterval, stream, functionCall, functions
    }
}

// ───────────────────────────────────────────────────────────
// MARK: - Function Definitions (отправляются в GigaChat)
// ───────────────────────────────────────────────────────────

nonisolated struct GigaFunction: Encodable, Sendable {
    let name: String
    let description: String
    let parameters: GigaFunctionParameters

    /// Примеры вызова (опционально, улучшают качество распознавания)
    let fewShotExamples: [GigaFunctionExample]?

    /// Описание того, что возвращает функция (опционально).
    let returnParameters: GigaFunctionParameters?

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name,        forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(parameters,  forKey: .parameters)
        try c.encodeIfPresent(fewShotExamples,  forKey: .fewShotExamples)
        try c.encodeIfPresent(returnParameters, forKey: .returnParameters)
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, parameters, fewShotExamples, returnParameters
    }
}

nonisolated struct GigaFunctionParameters: Encodable, Sendable {
    let properties: [String: GigaFunctionProperty]
    /// Обязательные поля (по умолчанию все поля считаются необязательными).
    let required: [String]?

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(properties, forKey: .properties)
        try c.encodeIfPresent(required, forKey: .required)
    }

    private enum CodingKeys: String, CodingKey {
        case properties, required
    }
}

nonisolated struct GigaFunctionProperty: Encodable, Sendable {
    let type: String
    let description: String
}

nonisolated struct GigaFunctionExample: Encodable, Sendable {
    let request: String
    let params: [String: String]
}
