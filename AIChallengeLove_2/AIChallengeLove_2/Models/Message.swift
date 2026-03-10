//
//  Message.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/3/25.
//

import Foundation

nonisolated struct Message: Codable, Sendable, Identifiable {
    let id: UUID
    let role: Role
    let content: String

    /// Если true — сообщение показывается в чате, но НЕ отправляется в API.
    /// Используется для уведомлений о смене стадии задачи.
    var isTransitionMarker: Bool

    /// Если true — сообщение скрыто в UI (не попадает в effectiveMessages()),
    /// но включается в API-запросы как контекст первого сообщения стадии.
    var isStageContext: Bool

    /// Время создания сообщения — отображается рядом с пузырём в чате.
    var timestamp: Date

    init(id: UUID = UUID(),
         role: Role,
         content: String,
         isTransitionMarker: Bool = false,
         isStageContext: Bool = false,
         timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.isTransitionMarker = isTransitionMarker
        self.isStageContext = isStageContext
        self.timestamp = timestamp
    }

    // Обратная совместимость: старые сообщения без id/timestamp/isStageContext получают дефолты
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.role = try container.decode(Role.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.isTransitionMarker = (try? container.decode(Bool.self, forKey: .isTransitionMarker)) ?? false
        self.isStageContext = (try? container.decode(Bool.self, forKey: .isStageContext)) ?? false
        self.timestamp = (try? container.decode(Date.self, forKey: .timestamp)) ?? Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, isTransitionMarker, isStageContext, timestamp
    }
}
