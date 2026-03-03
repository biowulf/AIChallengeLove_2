//
//  Branch.swift
//  AIChallengeLove_2
//

import Foundation

struct Checkpoint: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let messageCount: Int
    let createdAt: Date

    init(id: UUID = UUID(), name: String, messageCount: Int, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.messageCount = messageCount
        self.createdAt = createdAt
    }
}

struct Branch: Codable, Identifiable, Sendable {
    let id: UUID
    let checkpointId: UUID
    let name: String
    var messages: [Message]
    let createdAt: Date

    init(id: UUID = UUID(), checkpointId: UUID, name: String, messages: [Message] = [], createdAt: Date = Date()) {
        self.id = id
        self.checkpointId = checkpointId
        self.name = name
        self.messages = messages
        self.createdAt = createdAt
    }
}
