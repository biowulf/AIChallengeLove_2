//
//  LongTermMemory.swift
//  AIChallengeLove_2
//

import Foundation

// MARK: - Категории долговременной памяти

enum LongTermCategory: String, Codable, Sendable, CaseIterable {
    case userProfile    // Имя, возраст, профессия, местоположение
    case preferences    // Стиль общения, предпочтения формата ответов
    case decisions      // Важные решения и выводы
    case knowledge      // Накопленные факты и паттерны

    var label: String {
        switch self {
        case .userProfile:  return "Профиль"
        case .preferences:  return "Предпочтения"
        case .decisions:    return "Решения"
        case .knowledge:    return "Знания"
        }
    }
}

// MARK: - Запись долговременной памяти

struct LongTermMemoryEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let category: LongTermCategory
    let key: String
    let value: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         category: LongTermCategory = .knowledge,
         key: String,
         value: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.category = category
        self.key = key
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Долговременная память

/// Долговременная память — профиль пользователя и знания, сохраняющиеся между диалогами.
/// НЕ очищается при clearChat(). Только по явному запросу пользователя.
struct LongTermMemory: Codable, Sendable {
    var entries: [LongTermMemoryEntry]
    var lastExtractionAt: Date?

    init(entries: [LongTermMemoryEntry] = [], lastExtractionAt: Date? = nil) {
        self.entries = entries
        self.lastExtractionAt = lastExtractionAt
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Форматирует долговременную память для system prompt, группируя по категориям
    func asSystemPromptText() -> String {
        guard !entries.isEmpty else { return "" }

        let grouped = Dictionary(grouping: entries, by: { $0.category })
        var parts: [String] = []

        for category in LongTermCategory.allCases {
            guard let categoryEntries = grouped[category], !categoryEntries.isEmpty else { continue }
            let items = categoryEntries
                .map { "- \($0.key): \($0.value)" }
                .joined(separator: "\n")
            parts.append("\(category.label):\n\(items)")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Объединяет новые записи с существующими. Дедупликация по key + category.
    mutating func mergeEntries(_ newEntries: [LongTermMemoryEntry]) {
        for newEntry in newEntries {
            if let idx = entries.firstIndex(where: {
                $0.key.lowercased() == newEntry.key.lowercased() &&
                $0.category == newEntry.category
            }) {
                // Обновляем существующую запись, сохраняя id и createdAt
                entries[idx] = LongTermMemoryEntry(
                    id: entries[idx].id,
                    category: newEntry.category,
                    key: newEntry.key,
                    value: newEntry.value,
                    createdAt: entries[idx].createdAt,
                    updatedAt: Date()
                )
            } else {
                entries.append(newEntry)
            }
        }
    }
}
