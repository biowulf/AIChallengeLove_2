//
//  YAResponse.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/10/25.
//

import Foundation

// Основная структура ответа
nonisolated struct YAResponse: Codable, Sendable {
    let result: YAResult
}

// Вложенная структура для поля "result"
nonisolated struct YAResult: Codable, Sendable {
    let alternatives: [YAAlternative]
    let usage: YAUsage
    let modelVersion: String
}

// Структура для элемента массива "alternatives"
nonisolated struct YAAlternative: Codable, Sendable {
    let message: YAMessage
    let status: String
}

// Структура для поля "usage"
nonisolated struct YAUsage: Codable, Sendable {
    /// Количество токенов в текстовой части входных данных модели.
    let inputTextTokens: String
    /// Количество токенов в сгенерированном варианте автодополнения.
    let completionTokens: String
    /// Общее количество токенов, включая все входные токены и все сгенерированные токены.
    let totalTokens: String
    /// Предоставляет дополнительную информацию о том, как использовались токены завершения.
    let completionTokensDetails: YACompletionTokensDetails
}

// Вложенная структура для "completionTokensDetails"
nonisolated struct YACompletionTokensDetails: Codable, Sendable {
    /// Количество токенов, используемых специально для внутренних рассуждений, выполняемых моделью.
    let reasoningTokens: String
}
