//
//  GigaChatModel.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/3/25.
//

enum GigaChatModel: String, CaseIterable {
    case chat2 = "GigaChat-2"
    case chat2Pro = "GigaChat-2-Pro"
    case chat2Max = "GigaChat-2-Max"
}

extension GigaChatModel: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status?.lowercased() {
        case "GigaChat-2": self = .chat2
        case "GigaChat-2-Pro": self = .chat2Pro
        case "GigaChat-2-Max": self = .chat2Pro
        default:
            self = .chat2
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
