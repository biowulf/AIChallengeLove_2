//
//  Message.swift
//  AI_Challenge_Love_2
//

import Foundation

// ───────────────────────────────────────────────────────────
// MARK: - AnyCodingKey (вспомогательный ключ для произвольных словарей)
// ───────────────────────────────────────────────────────────

private extension String {
    /// Конвертирует camelCase → snake_case.
    /// Нужно потому что JSONDecoder с convertFromSnakeCase возвращает
    /// конвертированные ключи из allKeys (everyMinutes вместо every_minutes).
    func camelToSnakeCase() -> String {
        var result = ""
        for (i, ch) in self.enumerated() {
            if ch.isUppercase && i > 0 {
                result += "_" + ch.lowercased()
            } else {
                result += ch.lowercased()
            }
        }
        return result
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// ───────────────────────────────────────────────────────────
// MARK: - JSONValue (рекурсивное декодирование/кодирование любого JSON)
// ───────────────────────────────────────────────────────────

/// Декодирует произвольный JSON-узел: примитив, массив или объект.
/// Нужен чтобы `arguments` из GigaChat (массивы, вложенные объекты) не терялись.
private enum JSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: any Decoder) throws {
        // Объект
        if let c = try? decoder.container(keyedBy: AnyCodingKey.self) {
            var dict: [String: JSONValue] = [:]
            for key in c.allKeys {
                dict[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
            }
            self = .object(dict); return
        }
        // Массив
        if var c = try? decoder.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !c.isAtEnd { arr.append(try c.decode(JSONValue.self)) }
            self = .array(arr); return
        }
        // Примитивы — Bool раньше Int (NSNumber)
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                         { self = .null }
        else if let b = try? c.decode(Bool.self)   { self = .bool(b) }
        else if let i = try? c.decode(Int.self)    { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type")
        ) }
    }

    /// Конвертирует в `Any` для `JSONSerialization`.
    var toAny: Any {
        switch self {
        case .string(let s):  return s
        case .int(let i):     return i
        case .double(let d):  return d
        case .bool(let b):    return b
        case .null:           return NSNull()
        case .array(let a):   return a.map(\.toAny)
        case .object(let o):  return o.reduce(into: [String: Any]()) { $0[$1.key] = $1.value.toAny }
        }
    }
}

// ─── Вспомогательные функции для кодирования произвольного Any ───

private func encodeAnyValue(
    _ value: Any,
    into container: inout KeyedEncodingContainer<AnyCodingKey>,
    key: AnyCodingKey
) throws {
    switch value {
    case let b as Bool:         try container.encode(b, forKey: key)
    case let i as Int:          try container.encode(i, forKey: key)
    case let d as Double:       try container.encode(d, forKey: key)
    case let s as String:       try container.encode(s, forKey: key)
    case let arr as [Any]:
        var u = container.nestedUnkeyedContainer(forKey: key)
        for item in arr { try encodeAnyInArray(item, into: &u) }
    case let dict as [String: Any]:
        var nested = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)
        for (k, v) in dict {
            if let ck = AnyCodingKey(stringValue: k) {
                try encodeAnyValue(v, into: &nested, key: ck)
            }
        }
    default: break
    }
}

private func encodeAnyInArray(_ value: Any, into container: inout UnkeyedEncodingContainer) throws {
    switch value {
    case let b as Bool:         try container.encode(b)
    case let i as Int:          try container.encode(i)
    case let d as Double:       try container.encode(d)
    case let s as String:       try container.encode(s)
    case let arr as [Any]:
        var u = container.nestedUnkeyedContainer()
        for item in arr { try encodeAnyInArray(item, into: &u) }
    case let dict as [String: Any]:
        var nested = container.nestedContainer(keyedBy: AnyCodingKey.self)
        for (k, v) in dict {
            if let ck = AnyCodingKey(stringValue: k) {
                try encodeAnyValue(v, into: &nested, key: ck)
            }
        }
    default: break
    }
}

// ───────────────────────────────────────────────────────────
// MARK: - AssistantFunctionCall
// ───────────────────────────────────────────────────────────

/// Поле `function_call` в ответе ассистента когда GigaChat хочет вызвать инструмент.
///
/// GigaChat API отдаёт `arguments` как **JSON-объект** `{"location":"Москва"}`,
/// а не строку. Декодируем объект и нормализуем в JSON-строку для MCP.
nonisolated struct AssistantFunctionCall: Sendable {
    let name: String
    /// Аргументы в виде JSON-строки, готовой для передачи в `MCPManager.callTool`.
    /// Пример: `"{\"location\":\"Москва\"}"`.
    let arguments: String
}

extension AssistantFunctionCall: Codable {
    private enum CodingKeys: String, CodingKey { case name, arguments }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)

        // GigaChat отдаёт arguments как JSON-объект — сохраняем типы как есть.
        // ВАЖНО: decoder использует convertFromSnakeCase, поэтому allKeys возвращает
        // уже сконвертированные ключи: every_minutes → everyMinutes.
        // Конвертируем обратно в snake_case чтобы сервер получил оригинальные имена.
        // Декодируем arguments как произвольный JSON-объект (включая массивы и вложенные объекты).
        // JSONValue рекурсивно обходит любую структуру — примитивы, массивы, объекты.
        if let nestedC = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .arguments) {
            var dict: [String: Any] = [:]
            for key in nestedC.allKeys {
                let apiKey = key.stringValue.camelToSnakeCase()
                if let jsonValue = try? nestedC.decode(JSONValue.self, forKey: key) {
                    dict[apiKey] = jsonValue.toAny
                }
            }
            let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
            self.arguments = String(data: data, encoding: .utf8) ?? "{}"
        } else {
            self.arguments = "{}"
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)

        // При отправке контекста обратно в GigaChat передаём arguments как объект.
        // encodeAnyValue рекурсивно кодирует любые вложенные массивы и объекты.
        if let data = arguments.data(using: .utf8),
           let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var nested = c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .arguments)
            for (key, value) in jsonObj {
                if let k = AnyCodingKey(stringValue: key) {
                    try encodeAnyValue(value, into: &nested, key: k)
                }
            }
        } else {
            try c.encode(arguments, forKey: .arguments)
        }
    }
}

// ───────────────────────────────────────────────────────────
// MARK: - Message
// ───────────────────────────────────────────────────────────

nonisolated struct Message: Sendable, Identifiable {
    let id: UUID
    let role: Role
    let content: String

    /// Сообщение показывается в UI, но НЕ отправляется в API.
    /// Используется для уведомлений о смене стадии задачи.
    var isTransitionMarker: Bool

    /// Сообщение скрыто в UI, но включается в API-запросы как контекст стадии.
    var isStageContext: Bool

    /// Лог вызова MCP-инструмента: отображается в UI, НЕ отправляется в API.
    var isToolLog: Bool

    /// Время создания — отображается рядом с пузырём в чате.
    var timestamp: Date

    /// Заполнен когда `finish_reason == "function_call"`.
    var functionCall: AssistantFunctionCall?

    /// Обязательно для сообщений с `role == .function` — имя вызванной функции.
    var name: String?

    init(id: UUID = UUID(),
         role: Role,
         content: String,
         isTransitionMarker: Bool = false,
         isStageContext: Bool = false,
         isToolLog: Bool = false,
         timestamp: Date = Date(),
         functionCall: AssistantFunctionCall? = nil,
         name: String? = nil) {
        self.id                 = id
        self.role               = role
        self.content            = content
        self.isTransitionMarker = isTransitionMarker
        self.isStageContext     = isStageContext
        self.isToolLog          = isToolLog
        self.timestamp          = timestamp
        self.functionCall       = functionCall
        self.name               = name
    }
}

// MARK: - Codable (локальное хранение — полный набор полей)

extension Message: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, role, content
        case isTransitionMarker, isStageContext, isToolLog, timestamp
        case functionCall, name
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Локальные поля — нет в API-ответах GigaChat, используем дефолты.
        self.id                 = (try? c.decode(UUID.self,  forKey: .id))                 ?? UUID()
        self.isTransitionMarker = (try? c.decode(Bool.self,  forKey: .isTransitionMarker)) ?? false
        self.isStageContext     = (try? c.decode(Bool.self,  forKey: .isStageContext))     ?? false
        self.isToolLog          = (try? c.decode(Bool.self,  forKey: .isToolLog))          ?? false
        self.timestamp          = (try? c.decode(Date.self,  forKey: .timestamp))          ?? Date()

        // API-поля.
        self.role    = try c.decode(Role.self,    forKey: .role)
        self.content = (try? c.decode(String.self, forKey: .content)) ?? ""
        self.name    = try? c.decode(String.self, forKey: .name)

        if c.contains(.functionCall) {
            self.functionCall = try? c.decode(AssistantFunctionCall.self, forKey: .functionCall)
        } else {
            self.functionCall = nil
        }
    }

    /// Полное кодирование — используется ТОЛЬКО для локального хранения (MessageStorage).
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                 forKey: .id)
        try c.encode(isTransitionMarker, forKey: .isTransitionMarker)
        try c.encode(isStageContext,     forKey: .isStageContext)
        try c.encode(isToolLog,          forKey: .isToolLog)
        try c.encode(timestamp,          forKey: .timestamp)
        try c.encode(role,               forKey: .role)
        try c.encode(content,            forKey: .content)
        try c.encodeIfPresent(functionCall, forKey: .functionCall)
        try c.encodeIfPresent(name,         forKey: .name)
    }
}

// MARK: - APIMessage (отправляется в GigaChat — только поля из документации)

/// Лёгкое DTO для API-запросов. Содержит только поля которые принимает GigaChat:
/// `role`, `content`, `name`, `function_call`.
nonisolated struct APIMessage: Encodable, Sendable {
    let role:         Role
    let content:      String
    let functionCall: AssistantFunctionCall?
    let name:         String?

    init(from message: Message) {
        self.role         = message.role
        self.content      = message.content
        self.functionCall = message.functionCall
        self.name         = message.name
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role,    forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(functionCall, forKey: .functionCall)
        try c.encodeIfPresent(name,         forKey: .name)
    }

    private enum CodingKeys: String, CodingKey {
        case role, content, functionCall, name
    }
}

extension Array where Element == Message {
    /// Конвертирует массив `Message` в `[APIMessage]` для отправки в GigaChat.
    var asAPIMessages: [APIMessage] { map { APIMessage(from: $0) } }
}
