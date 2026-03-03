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

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    // Обратная совместимость: старые сообщения без id получают случайный UUID
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.role = try container.decode(Role.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content
    }
}
