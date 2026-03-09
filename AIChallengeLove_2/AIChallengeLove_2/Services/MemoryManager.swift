//
//  MemoryManager.swift
//  AIChallengeLove_2
//

import Foundation

/// Оркестратор трёх слоёв памяти:
/// - ShortTermMemory (Layer 1) — sliding window поверх messages
/// - WorkingMemory   (Layer 2) — контекст текущей задачи
/// - LongTermMemory  (Layer 3) — профиль и знания между диалогами
final class MemoryManager {

    // MARK: - State

    var shortTermMemory: ShortTermMemory
    var workingMemory: WorkingMemory
    var longTermMemory: LongTermMemory

    /// Через сколько обменов извлекать долговременную память
    private let longTermExtractionInterval = 5
    private var exchangesSinceLastLongTermExtraction = 0

    private let storage: MessageStorage

    // MARK: - Init

    init(storage: MessageStorage, windowSize: Int) {
        self.storage = storage
        self.shortTermMemory = ShortTermMemory(windowSize: windowSize)
        self.workingMemory = storage.loadWorkingMemory()
        self.longTermMemory = storage.loadLongTermMemory()
    }

    // MARK: - Context Composition

    /// Собирает полный массив сообщений для API из всех 3 слоёв.
    /// Гарантирует ровно один system message в результате.
    func composeMessagesForAPI(allMessages: [Message]) -> [Message] {
        var result: [Message] = []

        // Объединяем Layer 3 + Layer 2 в один system message
        var systemParts: [String] = []

        if !longTermMemory.isEmpty {
            systemParts.append(
                "Долговременная память о пользователе. Используй эту информацию " +
                "для персонализации ответов:\n\n\(longTermMemory.asSystemPromptText())"
            )
        }

        if !workingMemory.isEmpty {
            systemParts.append(
                "Контекст текущей задачи (рабочая память):\n\n\(workingMemory.asSystemPromptText())"
            )
        }

        if !systemParts.isEmpty {
            result.append(Message(
                role: .system,
                content: systemParts.joined(separator: "\n\n---\n\n")
            ))
        }

        // Layer 1: Краткосрочная память (последние N сообщений)
        let recentMessages = shortTermMemory.recentMessages(from: allMessages)
        result.append(contentsOf: recentMessages)

        return result
    }

    // MARK: - Working Memory Extraction

    /// Промпт для AI-извлечения рабочей памяти
    func buildWorkingMemoryExtractionPrompt() -> String {
        return """
            Ты — помощник для анализа контекста текущего диалога. \
            Проанализируй последние сообщения и извлеки:
            1. currentGoal — текущая задача или цель пользователя (одно предложение). \
               Если явной задачи нет, оставь пустую строку.
            2. entities — список ключевых сущностей (имена, термины, URL, числа) \
               упомянутых в разговоре. Максимум 10.
            3. notes — важные промежуточные результаты, уточнения или контекст, \
               который нужен для продолжения разговора. Максимум 5 заметок.
            4. activeTopic — краткое название текущей темы обсуждения (2-5 слов).

            Ответь строго в формате JSON (без markdown):
            {
                "currentGoal": "...",
                "entities": ["...", "..."],
                "notes": ["...", "..."],
                "activeTopic": "..."
            }

            Если какое-то поле не применимо, используй пустую строку или пустой массив. \
            Пиши на том же языке, на котором ведётся беседа.
            """
    }

    /// Парсит JSON-ответ AI в WorkingMemory
    func parseWorkingMemoryResponse(_ json: String) -> WorkingMemory? {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8) else { return nil }

        struct RawWorkingMemory: Decodable {
            let currentGoal: String?
            let entities: [String]?
            let notes: [String]?
            let activeTopic: String?
        }

        guard let raw = try? JSONDecoder().decode(RawWorkingMemory.self, from: data) else {
            return nil
        }

        return WorkingMemory(
            currentGoal: raw.currentGoal ?? "",
            entities: raw.entities ?? [],
            notes: raw.notes ?? [],
            activeTopic: raw.activeTopic ?? "",
            updatedAt: Date()
        )
    }

    /// Обновляет рабочую память и сохраняет
    func updateWorkingMemory(_ newMemory: WorkingMemory) {
        workingMemory = newMemory
        storage.saveWorkingMemory(workingMemory)
    }

    // MARK: - Long-term Memory Extraction

    /// Пора ли извлекать долговременную память (каждые N обменов)
    func shouldExtractLongTermMemory() -> Bool {
        exchangesSinceLastLongTermExtraction += 1
        return exchangesSinceLastLongTermExtraction >= longTermExtractionInterval
    }

    /// Сбрасывает счётчик после извлечения
    func resetLongTermExtractionCounter() {
        exchangesSinceLastLongTermExtraction = 0
    }

    /// Промпт для AI-извлечения долговременной памяти
    func buildLongTermMemoryExtractionPrompt(existingMemory: String) -> String {
        return """
            Ты — помощник для построения долговременного профиля пользователя. \
            Проанализируй диалог и извлеки информацию, которую стоит запомнить \
            о пользователе НАВСЕГДА (между разными разговорами):

            Категории:
            - userProfile: имя, возраст, профессия, местоположение, образование
            - preferences: стиль общения, предпочтения по формату ответов, язык
            - decisions: важные решения, выводы, договорённости
            - knowledge: накопленные факты, паттерны поведения

            Текущая долговременная память (не дублируй, только обновляй или добавляй):
            \(existingMemory.isEmpty ? "(пока пуста)" : existingMemory)

            Ответь строго в формате JSON массива (без markdown):
            [{"category": "userProfile|preferences|decisions|knowledge", \
              "key": "название", "value": "значение"}]

            Если новой долговременной информации нет, верни пустой массив []. \
            Пиши на том же языке, на котором ведётся беседа. \
            Максимум 5 новых записей за раз.
            
            ответ строго только JSON
            """
    }

    /// Парсит JSON-ответ AI в массив LongTermMemoryEntry
    func parseLongTermMemoryResponse(_ json: String) -> [LongTermMemoryEntry]? {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8) else { return nil }

        struct RawEntry: Decodable {
            let category: String
            let key: String
            let value: String
        }

        guard let rawEntries = try? JSONDecoder().decode([RawEntry].self, from: data) else {
            return nil
        }

        return rawEntries.compactMap { raw in
            guard let category = LongTermCategory(rawValue: raw.category) else { return nil }
            return LongTermMemoryEntry(category: category, key: raw.key, value: raw.value)
        }
    }

    /// Объединяет новые записи долговременной памяти и сохраняет
    func updateLongTermMemory(with newEntries: [LongTermMemoryEntry]) {
        longTermMemory.mergeEntries(newEntries)
        longTermMemory.lastExtractionAt = Date()
        storage.saveLongTermMemory(longTermMemory)
    }

    // MARK: - Clearing

    /// Очищает краткосрочную и рабочую память (при clearChat). Долговременная — остаётся.
    func clearConversationMemory() {
        workingMemory = WorkingMemory()
        storage.saveWorkingMemory(workingMemory)
        exchangesSinceLastLongTermExtraction = 0
    }

    /// Явная очистка долговременной памяти (только по запросу пользователя)
    func clearLongTermMemory() {
        longTermMemory = LongTermMemory()
        storage.saveLongTermMemory(longTermMemory)
    }

    /// Обновляет размер окна краткосрочной памяти
    func updateWindowSize(_ newSize: Int) {
        shortTermMemory.windowSize = newSize
    }
}
