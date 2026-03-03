//
//  StickyFact.swift
//  AIChallengeLove_2
//

import Foundation

struct StickyFact: Codable, Identifiable, Sendable {
    let id: UUID
    let key: String
    let value: String
    let updatedAt: Date

    init(id: UUID = UUID(), key: String, value: String, updatedAt: Date = Date()) {
        self.id = id
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}
