//
//  DialogLine.swift
//  AIChallengeLove_2
//

import Foundation

struct DialogLine: Codable, Identifiable, Sendable {
    let id: UUID
    var topic: String
    var messages: [Message]
    let createdAt: Date

    init(id: UUID = UUID(), topic: String, messages: [Message] = [], createdAt: Date = Date()) {
        self.id = id
        self.topic = topic
        self.messages = messages
        self.createdAt = createdAt
    }
}
