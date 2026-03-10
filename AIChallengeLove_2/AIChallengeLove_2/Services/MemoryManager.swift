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

    // Единый system prompt (замена profile + invariants)
    var systemPromptConfig: SystemPromptConfig

    // Состояние задачи (state machine)
    var taskState: TaskState

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
        self.systemPromptConfig = storage.loadSystemPromptConfig()
        self.taskState = storage.loadTaskState()
    }

    // MARK: - Context Composition

    /// Собирает полный массив сообщений для API из всех слоёв.
    /// Гарантирует ровно один system message в результате.
    /// Порядок приоритета: system prompt > долговременная память > рабочая память > задача (фазо-зависимый)
    func composeMessagesForAPI(allMessages: [Message]) -> [Message] {
        var result: [Message] = []

        var systemParts: [String] = []

        // 1. Пользовательский system prompt (объединённые профиль + инварианты)
        if systemPromptConfig.isActive, !systemPromptConfig.isEmpty {
            systemParts.append(systemPromptConfig.customSystemPrompt)
        }

        // 2. Долговременная память
        if !longTermMemory.isEmpty {
            systemParts.append(
                "Долговременная память о пользователе. Используй эту информацию " +
                "для персонализации ответов:\n\n\(longTermMemory.asSystemPromptText())"
            )
        }

        // 3. Рабочая память
        if !workingMemory.isEmpty {
            systemParts.append(
                "Контекст текущей задачи (рабочая память):\n\n\(workingMemory.asSystemPromptText())"
            )
        }

        // 4. Состояние задачи — фазо-зависимый промпт
        if taskState.isActive {
            let phasePrompt = buildPhasePrompt(for: taskState)
            systemParts.append(phasePrompt)
        }

        if !systemParts.isEmpty {
            result.append(Message(
                role: .system,
                content: systemParts.joined(separator: "\n\n---\n\n")
            ))
        }

        // Краткосрочная память (последние N сообщений)
        let recentMessages = shortTermMemory.recentMessages(from: allMessages)
        result.append(contentsOf: recentMessages)

        return result
    }

    // MARK: - Phase-dependent Prompt

    /// Генерирует промпт для AI на основе текущей стадии задачи.
    /// Каждый промпт содержит маркер, который AI пишет в конце ответа.
    private func buildPhasePrompt(for state: TaskState) -> String {
        let desc = state.taskDescription.isEmpty ? "(не указана)" : state.taskDescription
        let stepsText = state.steps.isEmpty ? "(нет шагов)" : state.steps.enumerated().map { idx, step in
            let marker = step.isCompleted ? "[x]" : (idx == state.currentStepIndex ? "[>]" : "[ ]")
            return "\(marker) \(step.description)"
        }.joined(separator: "\n")

        switch state.currentPhase {
        case .research:
            return """
                ══════════════════════════════════════
                СТАДИЯ: 🔍 RESEARCH (Исследование)
                Задача: \(desc)
                ══════════════════════════════════════

                ⚠️ ТОЛЬКО СБОР ИНФОРМАЦИИ — никакого кода и готовых решений!

                Твои действия:
                1. Проанализируй задачу, уточни требования.
                2. Изучи что нужно для реализации: зависимости, структуры, API, ограничения.
                3. Задай уточняющие вопросы если чего-то не хватает.
                4. Составь резюме: что известно, что нужно сделать, возможные подходы.

                Когда исследование завершено — в самом конце ответа напиши:

                ИССЛЕДОВАНИЕ ЗАВЕРШЕНО

                ❌ ЗАПРЕЩЕНО: писать код, реализовывать решение.
                ✅ РАЗРЕШЕНО: задавать вопросы, анализировать, составлять резюме требований.
                """

        case .plan:
            return """
                ══════════════════════════════════════
                СТАДИЯ: 📋 PLAN (Планирование)
                Задача: \(desc)
                ══════════════════════════════════════

                ⚠️ ТОЛЬКО ПЛАН — никакого кода!

                Твои действия:
                1. На основе результатов исследования составь детальный пошаговый план.
                2. Разбей на пронумерованные шаги — каждый шаг одна логическая единица работы.
                3. Для каждого шага: что именно создаётся/изменяется, в каком файле, какой результат.
                4. Укажи зависимости между шагами и возможные риски.

                Когда план готов — в самом конце ответа напиши:

                ПЛАН ГОТОВ

                ❌ ЗАПРЕЩЕНО: писать код, реализовывать функции.
                ✅ РАЗРЕШЕНО: описывать шаги, структуру, интерфейсы словами.
                """

        case .executing:
            return """
                ══════════════════════════════════════
                СТАДИЯ: ⚙️ EXECUTING (Выполнение)
                Задача: \(desc)
                Шаги плана:
                \(stepsText)
                ══════════════════════════════════════

                Твои действия:
                1. Реализуй план шаг за шагом согласно плану выше.
                2. Пиши полный рабочий код — без заглушек и TODO.
                3. Объясняй ключевые решения по ходу.
                4. Реализуй все шаги плана полностью.

                Когда ВСЯ реализация завершена — в самом конце ответа напиши:

                ВЫПОЛНЕНИЕ ЗАВЕРШЕНО

                Если нужно пересмотреть исследование — напиши: НУЖНО ПЕРЕИССЛЕДОВАНИЕ
                """

        case .validation:
            return """
                ══════════════════════════════════════
                СТАДИЯ: ✅ VALIDATION (Проверка)
                Задача: \(desc)
                Шаги плана:
                \(stepsText)
                ══════════════════════════════════════

                Твои действия:
                1. Сверь написанный код с планом — все ли шаги выполнены?
                2. Проверь логику, крайние случаи, возможные ошибки.
                3. Убедись, что код решает исходную задачу.

                Если нашёл проблемы:
                - Опиши их СЛОВАМИ (не переписывай код!)
                - Если нужны доработки → напиши: НУЖНЫ ДОРАБОТКИ
                - Если нужно пересмотреть исследование → напиши: НУЖНО ПЕРЕИССЛЕДОВАНИЕ

                Если всё корректно и задача выполнена — напиши:

                ПРОВЕРКА ПРОЙДЕНА
                """

        case .report:
            return """
                ══════════════════════════════════════
                СТАДИЯ: 📝 REPORT (Отчёт)
                Задача: \(desc)
                ══════════════════════════════════════

                Твои действия:
                1. Подведи итоги: что сделано, какие решения приняты.
                2. Перечисли все изменённые/созданные файлы.
                3. Укажи что осталось за рамками (если есть).
                4. Дай краткие инструкции по использованию результата.

                Когда отчёт готов — напиши:

                ОТЧЁТ ГОТОВ
                """

        case .idle, .done:
            return ""
        }
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

    // MARK: - Task State

    /// Обновляет состояние задачи и сохраняет
    func updateTaskState(_ newState: TaskState) {
        taskState = newState
        storage.saveTaskState(taskState)
    }

    /// Сбрасывает состояние задачи (при clearChat)
    func clearTaskState() {
        taskState = TaskState()
        storage.saveTaskState(taskState)
    }

    // MARK: - System Prompt Config

    /// Обновляет system prompt config и сохраняет
    func updateSystemPromptConfig(_ config: SystemPromptConfig) {
        systemPromptConfig = config
        storage.saveSystemPromptConfig(systemPromptConfig)
    }

    // MARK: - Clearing

    /// Очищает краткосрочную, рабочую память и состояние задачи (при clearChat).
    /// Долговременная память и system prompt — остаются.
    func clearConversationMemory() {
        workingMemory = WorkingMemory()
        storage.saveWorkingMemory(workingMemory)
        taskState = TaskState()
        storage.saveTaskState(taskState)
        exchangesSinceLastLongTermExtraction = 0
    }

    /// Явная очистка долговременной памяти (только по запросу пользователя)
    func clearLongTermMemory() {
        longTermMemory.clear()
        storage.saveLongTermMemory(longTermMemory)
    }

    /// Обновляет размер окна краткосрочной памяти
    func updateWindowSize(_ newSize: Int) {
        shortTermMemory.windowSize = newSize
    }
}
