//
//  GPTAPI.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/10/25.
//

enum GPTAPI: String, CaseIterable {
    case gigachat
    case yandex
}

extension GPTAPI: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status?.lowercased() {
        case "gigachat": self = .gigachat
        case "yandex": self = .yandex
        default:
            self = .gigachat
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
