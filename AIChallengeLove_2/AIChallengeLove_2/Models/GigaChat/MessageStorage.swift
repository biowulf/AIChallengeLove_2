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
    private let collapseTypeKey = "savedCollapseType"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Messages
    
    /// Сохранить сообщения в UserDefaults
    func saveMessages(_ messages: [Message]) {
        do {
            let data = try encoder.encode(messages)
            userDefaults.set(data, forKey: messagesKey)
        } catch {
            print("Ошибка сохранения сообщений: \(error.localizedDescription)")
        }
    }
    
    /// Загрузить сообщения из UserDefaults
    func loadMessages() -> [Message] {
        guard let data = userDefaults.data(forKey: messagesKey) else {
            return []
        }
        
        do {
            let messages = try decoder.decode([Message].self, from: data)
            return messages
        } catch {
            print("Ошибка загрузки сообщений: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Очистить сохранённые сообщения и резюме из UserDefaults
    func clearMessages() {
        userDefaults.removeObject(forKey: messagesKey)
        clearSummaries()
    }
    
    // MARK: - Info (Statistics)
    
    /// Сохранить статистику в UserDefaults
    func saveInfo(_ info: Info) {
        do {
            let data = try encoder.encode(info)
            userDefaults.set(data, forKey: infoKey)
        } catch {
            print("Ошибка сохранения статистики: \(error.localizedDescription)")
        }
    }
    
    /// Загрузить статистику из UserDefaults
    func loadInfo() -> Info {
        guard let data = userDefaults.data(forKey: infoKey) else {
            return Info()
        }
        
        do {
            let info = try decoder.decode(Info.self, from: data)
            return info
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

    // MARK: - CollapseType

    func saveCollapseType(_ type: CollapseType) {
        do {
            let data = try encoder.encode(type)
            userDefaults.set(data, forKey: collapseTypeKey)
        } catch {
            print("Ошибка сохранения типа сжатия: \(error.localizedDescription)")
        }
    }

    func loadCollapseType() -> CollapseType {
        guard let data = userDefaults.data(forKey: collapseTypeKey) else { return .none }
        do {
            return try decoder.decode(CollapseType.self, from: data)
        } catch { return .none }
    }

    /// Очистить статистику сессии из UserDefaults
    func clearSessionInfo(for api: GPTAPI) {
        var info = loadInfo()
        info.session[api] = SessionGPT(input: 0, output: 0, total: 0)
        saveInfo(info)
    }
}
