//
//  ShortTermMemory.swift
//  AIChallengeLove_2
//

import Foundation

/// Краткосрочная память — sliding window над последними N сообщениями текущего диалога.
/// Не хранит данные отдельно: работает как view поверх массива `messages`.
struct ShortTermMemory: Codable, Sendable {
    /// Максимальное количество сообщений в окне
    var windowSize: Int

    /// Возвращает последние N сообщений, выровненных по user/system
    func recentMessages(from allMessages: [Message]) -> [Message] {
        guard allMessages.count > windowSize else { return allMessages }
        var startIndex = max(0, allMessages.count - windowSize)
        // Выравниваем начало окна по user/system сообщению
        while startIndex < allMessages.count &&
              allMessages[startIndex].role != .user &&
              allMessages[startIndex].role != .system {
            startIndex += 1
        }
        return startIndex < allMessages.count
            ? Array(allMessages[startIndex...])
            : allMessages
    }
}
