//
//  SystemPromptConfig.swift
//  AIChallengeLove_2
//

import Foundation

/// Единый пользовательский system prompt, заменяющий отдельный профиль и инварианты.
/// Пользователь пишет произвольный текст, определяющий поведение ассистента.
struct SystemPromptConfig: Codable, Sendable {
    var customSystemPrompt: String
    var isActive: Bool

    init(customSystemPrompt: String = "", isActive: Bool = true) {
        self.customSystemPrompt = customSystemPrompt
        self.isActive = isActive
    }

    var isEmpty: Bool {
        customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
