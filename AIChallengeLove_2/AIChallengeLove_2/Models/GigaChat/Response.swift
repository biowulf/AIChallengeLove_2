//
//  Response.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/2/25.
//

import Foundation

nonisolated struct ResponsePayload: Decodable, Sendable {
    /// Массив ответов модели.
    let choices: [Choice]
    /// Дата и время создания ответа в формате unix timestamp.
    let created: Int
    /// Название и версия модели, которая сгенерировала ответ. Описание доступных моделей смотрите в разделе Модели GigaChat.
    /// При обращении к моделям в раннем доступе к названию модели нужно добавлять постфикс -preview. Например, GigaChat-Pro-preview.
    let model: String
    /// Данные об использовании модели. При запуске потоковой генерации, объект приходит в предпоследнем событии.
    let usage: Usage
    /// Название вызываемого метода
    let object: String
}

nonisolated struct Choice: Decodable, Sendable {
    let message: Message
    /// Индекс сообщения в массиве, начиная с ноля.
    let index: Int
    let finishReason: FinishReason
}

/// При работе в режиме потоковой генерации передается в предпоследнем событии со значением.
nonisolated enum FinishReason: String, Sendable {
    /// модель закончила формировать гипотезу и вернула полный ответ
    case stop
    /// достигнут лимит токенов в сообщении
    case length
    /// указывает, что при запросе была вызвана встроенная функция или сгенерированы аргументы для пользовательской функции
    case functionCall
    /// запрос попадает под тематические ограничения
    case blacklist
    /// ответ модели содержит невалидные аргументы пользовательской функции
    case error
}

extension FinishReason: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status?.lowercased() {
        case "stop": self = .stop
        case "length": self = .length
        case "function_call": self = .functionCall
        case "blacklist": self = .blacklist
        case "error": self = .error
        default:
            self = .error
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct Usage: Codable, Sendable {
    /// Количество токенов во входящем сообщении (роль user).
    let promptTokens: Int
    /// Количество токенов, сгенерированных моделью (роль assistant).
    let completionTokens: Int
    /// Количество ранее закэшированных токенов, которые были использованы при обработке запроса.
    /// Кэшированные токены вычитаются из общего числа оплачиваемых токенов (поле total_tokens).
    /// Модели GigaChat в течение некоторого времени сохраняют контекст запроса
    /// (историю сообщений массива messages, описание функций) с помощью кэширования токенов.
    /// Это позволяет повысить скорость ответа моделей и снизить стоимость работы с GigaChat API.
    /// Для повышения вероятности использования сохраненных токенов используйте кэширование запросов.
    let precachedPromptTokens: Int
    /// Общее число токенов, подлежащих тарификации, после вычитания кэшированных токенов (поле precached_prompt_tokens).
    let totalTokens: Int
}
