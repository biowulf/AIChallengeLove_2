//
//  Role.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/3/25.
//

enum Role: String {
    case system
    case user
    case assistant
    case function
}

extension Role: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status?.lowercased() {
        case "system": self = .system
        case "user": self = .user
        case "assistant": self = .assistant
        case "function": self = .function
        default:
            self = .user
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
