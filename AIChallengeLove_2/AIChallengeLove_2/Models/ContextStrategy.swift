//
//  ContextStrategy.swift
//  AIChallengeLove_2
//

enum ContextStrategy: String, CaseIterable, Codable {
    case none           // Без сжатия — отправлять все сообщения
    case slidingWindow  // Скользящее окно — последние N сообщений
    case gptSummary     // AI-резюме — суммаризация старых сообщений
    case stickyFacts    // Ключевые факты + последние N сообщений
    case branching      // Ветвление диалога — чекпоинты и ветки
    case memoryLayers   // Слои памяти — краткосрочная + рабочая + долговременная

    var label: String {
        switch self {
        case .none:          return "Без сжатия"
        case .slidingWindow: return "Скользящее окно"
        case .gptSummary:    return "AI-резюме"
        case .stickyFacts:   return "Ключевые факты"
        case .branching:     return "Авто-ветвление"
        case .memoryLayers:  return "Слои памяти"
        }
    }
}
