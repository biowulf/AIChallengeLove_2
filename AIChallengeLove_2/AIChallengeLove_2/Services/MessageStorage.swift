//
//  MessageStorage.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 02/25/26.
//

import Foundation

final class MessageStorage {
    private let userDefaults = UserDefaults.standard
    private let messagesKey = "savedMessages"
    private let infoKey = "savedInfo"
    private let summariesKey = "savedSummaries"
    private let contextStrategyKey = "savedContextStrategy"
    private let windowSizeKey = "savedWindowSize"
    private let factsKey = "savedFacts"
    private let checkpointsKey = "savedCheckpoints"
    private let branchesKey = "savedBranches"
    private let activeBranchIdKey = "savedActiveBranchId"
    private let dialogLinesKey = "savedDialogLines"
    private let activeLineIdKey = "savedActiveLineId"
    private let workingMemoryKey = "savedWorkingMemory"
    private let longTermMemoryKey = "savedLongTermMemory"
    private let userProfileKey = "savedUserProfile"
    private let taskStateKey = "savedTaskState"
    private let invariantsKey = "savedInvariants"
    private let systemPromptConfigKey = "savedSystemPromptConfig"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Messages

    func saveMessages(_ messages: [Message]) {
        do {
            let data = try encoder.encode(messages)
            userDefaults.set(data, forKey: messagesKey)
        } catch {
            print("Ошибка сохранения сообщений: \(error.localizedDescription)")
        }
    }

    func loadMessages() -> [Message] {
        guard let data = userDefaults.data(forKey: messagesKey) else {
            return []
        }
        do {
            return try decoder.decode([Message].self, from: data)
        } catch {
            print("Ошибка загрузки сообщений: \(error.localizedDescription)")
            return []
        }
    }

    func clearMessages() {
        userDefaults.removeObject(forKey: messagesKey)
        clearSummaries()
        clearFacts()
        clearBranches()
        clearDialogLines()
        clearWorkingMemory()
        clearTaskState()
        // НЕ очищаем долговременную память, профиль и инварианты — они живут между диалогами
    }

    // MARK: - Info (Statistics)

    func saveInfo(_ info: Info) {
        do {
            let data = try encoder.encode(info)
            userDefaults.set(data, forKey: infoKey)
        } catch {
            print("Ошибка сохранения статистики: \(error.localizedDescription)")
        }
    }

    func loadInfo() -> Info {
        guard let data = userDefaults.data(forKey: infoKey) else {
            return Info()
        }
        do {
            return try decoder.decode(Info.self, from: data)
        } catch {
            print("Ошибка загрузки статистики: \(error.localizedDescription)")
            return Info()
        }
    }

    // MARK: - Summaries

    func saveSummaries(_ summaries: [ConversationSummary]) {
        do {
            let data = try encoder.encode(summaries)
            userDefaults.set(data, forKey: summariesKey)
        } catch {
            print("Ошибка сохранения резюме: \(error.localizedDescription)")
        }
    }

    func loadSummaries() -> [ConversationSummary] {
        guard let data = userDefaults.data(forKey: summariesKey) else { return [] }
        do {
            return try decoder.decode([ConversationSummary].self, from: data)
        } catch {
            print("Ошибка загрузки резюме: \(error.localizedDescription)")
            return []
        }
    }

    func clearSummaries() {
        userDefaults.removeObject(forKey: summariesKey)
    }

    // MARK: - Context Strategy

    func saveContextStrategy(_ strategy: ContextStrategy) {
        do {
            let data = try encoder.encode(strategy)
            userDefaults.set(data, forKey: contextStrategyKey)
        } catch {
            print("Ошибка сохранения стратегии: \(error.localizedDescription)")
        }
    }

    func loadContextStrategy() -> ContextStrategy {
        guard let data = userDefaults.data(forKey: contextStrategyKey) else { return .none }
        do {
            return try decoder.decode(ContextStrategy.self, from: data)
        } catch {
            return .none
        }
    }

    // MARK: - Window Size

    func saveWindowSize(_ size: Int) {
        userDefaults.set(size, forKey: windowSizeKey)
    }

    func loadWindowSize() -> Int {
        let saved = userDefaults.integer(forKey: windowSizeKey)
        return saved > 0 ? saved : 10
    }

    // MARK: - Sticky Facts

    func saveFacts(_ facts: [StickyFact]) {
        do {
            let data = try encoder.encode(facts)
            userDefaults.set(data, forKey: factsKey)
        } catch {
            print("Ошибка сохранения фактов: \(error.localizedDescription)")
        }
    }

    func loadFacts() -> [StickyFact] {
        guard let data = userDefaults.data(forKey: factsKey) else { return [] }
        do {
            return try decoder.decode([StickyFact].self, from: data)
        } catch {
            print("Ошибка загрузки фактов: \(error.localizedDescription)")
            return []
        }
    }

    func clearFacts() {
        userDefaults.removeObject(forKey: factsKey)
    }

    // MARK: - Checkpoints

    func saveCheckpoints(_ checkpoints: [Checkpoint]) {
        do {
            let data = try encoder.encode(checkpoints)
            userDefaults.set(data, forKey: checkpointsKey)
        } catch {
            print("Ошибка сохранения чекпоинтов: \(error.localizedDescription)")
        }
    }

    func loadCheckpoints() -> [Checkpoint] {
        guard let data = userDefaults.data(forKey: checkpointsKey) else { return [] }
        do {
            return try decoder.decode([Checkpoint].self, from: data)
        } catch {
            print("Ошибка загрузки чекпоинтов: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Branches

    func saveBranches(_ branches: [Branch]) {
        do {
            let data = try encoder.encode(branches)
            userDefaults.set(data, forKey: branchesKey)
        } catch {
            print("Ошибка сохранения веток: \(error.localizedDescription)")
        }
    }

    func loadBranches() -> [Branch] {
        guard let data = userDefaults.data(forKey: branchesKey) else { return [] }
        do {
            return try decoder.decode([Branch].self, from: data)
        } catch {
            print("Ошибка загрузки веток: \(error.localizedDescription)")
            return []
        }
    }

    func saveActiveBranchId(_ id: UUID?) {
        if let id {
            userDefaults.set(id.uuidString, forKey: activeBranchIdKey)
        } else {
            userDefaults.removeObject(forKey: activeBranchIdKey)
        }
    }

    func loadActiveBranchId() -> UUID? {
        guard let str = userDefaults.string(forKey: activeBranchIdKey) else { return nil }
        return UUID(uuidString: str)
    }

    func clearBranches() {
        userDefaults.removeObject(forKey: checkpointsKey)
        userDefaults.removeObject(forKey: branchesKey)
        userDefaults.removeObject(forKey: activeBranchIdKey)
    }

    // MARK: - Dialog Lines

    func saveDialogLines(_ lines: [DialogLine]) {
        do {
            let data = try encoder.encode(lines)
            userDefaults.set(data, forKey: dialogLinesKey)
        } catch {
            print("Ошибка сохранения линий диалога: \(error.localizedDescription)")
        }
    }

    func loadDialogLines() -> [DialogLine] {
        guard let data = userDefaults.data(forKey: dialogLinesKey) else { return [] }
        do {
            return try decoder.decode([DialogLine].self, from: data)
        } catch {
            print("Ошибка загрузки линий диалога: \(error.localizedDescription)")
            return []
        }
    }

    func saveActiveLineId(_ id: UUID?) {
        if let id {
            userDefaults.set(id.uuidString, forKey: activeLineIdKey)
        } else {
            userDefaults.removeObject(forKey: activeLineIdKey)
        }
    }

    func loadActiveLineId() -> UUID? {
        guard let str = userDefaults.string(forKey: activeLineIdKey) else { return nil }
        return UUID(uuidString: str)
    }

    func clearDialogLines() {
        userDefaults.removeObject(forKey: dialogLinesKey)
        userDefaults.removeObject(forKey: activeLineIdKey)
    }

    // MARK: - Working Memory

    func saveWorkingMemory(_ memory: WorkingMemory) {
        do {
            let data = try encoder.encode(memory)
            userDefaults.set(data, forKey: workingMemoryKey)
        } catch {
            print("Ошибка сохранения рабочей памяти: \(error.localizedDescription)")
        }
    }

    func loadWorkingMemory() -> WorkingMemory {
        guard let data = userDefaults.data(forKey: workingMemoryKey) else {
            return WorkingMemory()
        }
        do {
            return try decoder.decode(WorkingMemory.self, from: data)
        } catch {
            print("Ошибка загрузки рабочей памяти: \(error.localizedDescription)")
            return WorkingMemory()
        }
    }

    func clearWorkingMemory() {
        userDefaults.removeObject(forKey: workingMemoryKey)
    }

    // MARK: - Long-term Memory

    func saveLongTermMemory(_ memory: LongTermMemory) {
        do {
            let data = try encoder.encode(memory)
            userDefaults.set(data, forKey: longTermMemoryKey)
        } catch {
            print("Ошибка сохранения долговременной памяти: \(error.localizedDescription)")
        }
    }

    func loadLongTermMemory() -> LongTermMemory {
        guard let data = userDefaults.data(forKey: longTermMemoryKey) else {
            return LongTermMemory()
        }
        do {
            return try decoder.decode(LongTermMemory.self, from: data)
        } catch {
            print("Ошибка загрузки долговременной памяти: \(error.localizedDescription)")
            return LongTermMemory()
        }
    }

    func clearLongTermMemory() {
        userDefaults.removeObject(forKey: longTermMemoryKey)
    }

    // MARK: - Session

    func clearSessionInfo(for api: GPTAPI) {
        var info = loadInfo()
        info.session[api] = SessionGPT(input: 0, output: 0, total: 0)
        saveInfo(info)
    }

    // MARK: - User Profile (legacy keys preserved for data compat)

    // MARK: - Task State

    func saveTaskState(_ state: TaskState) {
        do {
            let data = try encoder.encode(state)
            userDefaults.set(data, forKey: taskStateKey)
        } catch {
            print("Ошибка сохранения состояния задачи: \(error.localizedDescription)")
        }
    }

    func loadTaskState() -> TaskState {
        guard let data = userDefaults.data(forKey: taskStateKey) else {
            return TaskState()
        }
        do {
            return try decoder.decode(TaskState.self, from: data)
        } catch {
            print("Ошибка загрузки состояния задачи: \(error.localizedDescription)")
            return TaskState()
        }
    }

    func clearTaskState() {
        userDefaults.removeObject(forKey: taskStateKey)
    }

    // MARK: - Invariants (legacy keys preserved for data compat)

    // MARK: - System Prompt Config

    func saveSystemPromptConfig(_ config: SystemPromptConfig) {
        do {
            let data = try encoder.encode(config)
            userDefaults.set(data, forKey: systemPromptConfigKey)
        } catch {
            print("Ошибка сохранения system prompt config: \(error.localizedDescription)")
        }
    }

    func loadSystemPromptConfig() -> SystemPromptConfig {
        guard let data = userDefaults.data(forKey: systemPromptConfigKey) else {
            return SystemPromptConfig()
        }
        do {
            return try decoder.decode(SystemPromptConfig.self, from: data)
        } catch {
            print("Ошибка загрузки system prompt config: \(error.localizedDescription)")
            return SystemPromptConfig()
        }
    }

    func clearSystemPromptConfig() {
        userDefaults.removeObject(forKey: systemPromptConfigKey)
    }
}
