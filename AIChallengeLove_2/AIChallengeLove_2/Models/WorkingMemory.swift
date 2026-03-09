//
//  WorkingMemory.swift
//  AIChallengeLove_2
//

import Foundation

/// Рабочая память — контекст текущей задачи/сессии.
/// Извлекается AI из диалога. Живёт в рамках текущего разговора, очищается при clearChat().
struct WorkingMemory: Codable, Sendable {
    /// Текущая задача или цель пользователя
    var currentGoal: String

    /// Ключевые сущности из разговора (имена, термины, URL, числа)
    var entities: [String]

    /// Промежуточные результаты и заметки по контексту
    var notes: [String]

    /// Краткое название активной темы обсуждения
    var activeTopic: String

    /// Время последнего обновления
    var updatedAt: Date

    init(currentGoal: String = "",
         entities: [String] = [],
         notes: [String] = [],
         activeTopic: String = "",
         updatedAt: Date = Date()) {
        self.currentGoal = currentGoal
        self.entities = entities
        self.notes = notes
        self.activeTopic = activeTopic
        self.updatedAt = updatedAt
    }

    /// Есть ли значимые данные
    var isEmpty: Bool {
        currentGoal.isEmpty && entities.isEmpty && notes.isEmpty && activeTopic.isEmpty
    }

    /// Форматирует рабочую память для вставки в system prompt
    func asSystemPromptText() -> String {
        var parts: [String] = []
        if !currentGoal.isEmpty {
            parts.append("Текущая задача пользователя: \(currentGoal)")
        }
        if !activeTopic.isEmpty {
            parts.append("Активная тема: \(activeTopic)")
        }
        if !entities.isEmpty {
            parts.append("Ключевые сущности: \(entities.joined(separator: ", "))")
        }
        if !notes.isEmpty {
            parts.append("Заметки по контексту:\n" + notes.map { "- \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n")
    }
}
