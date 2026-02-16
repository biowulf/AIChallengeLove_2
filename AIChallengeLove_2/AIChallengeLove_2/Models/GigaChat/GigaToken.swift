//
//  GigaToken.swift
//  AIChallengeLove_2
//
//  Created by Bolyachev Rostislav on 2/16/26.
//

import Foundation

nonisolated struct GigaToken: Codable, Sendable {
    let accessToken: String
    let expiresAt: Date

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.accessToken = try container.decode(String.self, forKey: .accessToken)

        // Преобразование millisecond-based timestamp в дату
        let milliseconds = try container.decode(Int.self, forKey: .expiresAt)
        self.expiresAt = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)

    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)

        // Обратное преобразование даты обратно в миллисекунды
        let timeIntervalSince1970 = expiresAt.timeIntervalSince1970 * 1000
        try container.encode(Int(timeIntervalSince1970), forKey: .expiresAt)
    }
}
