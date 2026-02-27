//
//  ConversationSummary.swift
//  AIChallengeLove_2
//

import Foundation

nonisolated struct ConversationSummary: Codable, Sendable {
    let content: String
    let originalMessageCount: Int
    let createdAt: Date
}
