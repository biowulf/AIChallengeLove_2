//
//  Message.swift
//  AI_Challenge_Love_2
//

import Foundation

// ───────────────────────────────────────────────────────────
// MARK: - AnyCodingKey (вспомогательный ключ для произвольных словарей)
// ───────────────────────────────────────────────────────────

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
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

        // GigaChat отдаёт arguments как JSON-объект, нормализуем в строку.
        if let str = try? c.decode(String.self, forKey: .arguments) {
            // Редкий случай: уже строка
            self.arguments = str
        } else if let nestedC = try? c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .arguments) {
            // Стандартный случай: JSON-объект → собираем словарь → сериализуем
            var dict: [String: String] = [:]
            for key in nestedC.allKeys {
                if let v = try? nestedC.decode(String.self, forKey: key)  { dict[key.stringValue] = v }
                else if let v = try? nestedC.decode(Int.self, forKey: key)    { dict[key.stringValue] = String(v) }
                else if let v = try? nestedC.decode(Double.self, forKey: key) { dict[key.stringValue] = String(v) }
                else if let v = try? nestedC.decode(Bool.self, forKey: key)   { dict[key.stringValue] = String(v) }
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
        if let data = arguments.data(using: .utf8),
           let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var nested = c.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .arguments)
            for (key, value) in jsonObj {
                let k = AnyCodingKey(stringValue: key)!
                if let s = value as? String       { try nested.encode(s, forKey: k) }
                else if let i = value as? Int     { try nested.encode(i, forKey: k) }
                else if let d = value as? Double  { try nested.encode(d, forKey: k) }
                else if let b = value as? Bool    { try nested.encode(b, forKey: k) }
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
         timestamp: Date = Date(),
         functionCall: AssistantFunctionCall? = nil,
         name: String? = nil) {
        self.id                 = id
        self.role               = role
        self.content            = content
        self.isTransitionMarker = isTransitionMarker
        self.isStageContext     = isStageContext
        self.timestamp          = timestamp
        self.functionCall       = functionCall
        self.name               = name
    }
}

// MARK: Codable

extension Message: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, role, content
        case isTransitionMarker, isStageContext, timestamp
        case functionCall, name
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Локальные поля — нет в API-ответах GigaChat, используем дефолты.
        self.id                 = (try? c.decode(UUID.self,  forKey: .id))                ?? UUID()
        self.isTransitionMarker = (try? c.decode(Bool.self,  forKey: .isTransitionMarker)) ?? false
        self.isStageContext     = (try? c.decode(Bool.self,  forKey: .isStageContext))     ?? false
        self.timestamp          = (try? c.decode(Date.self,  forKey: .timestamp))          ?? Date()

        // API-поля — обязательны в API-ответах, опциональны в локальном хранилище.
        self.role               = try c.decode(Role.self,    forKey: .role)
        self.content            = (try? c.decode(String.self, forKey: .content))           ?? ""
        self.name               = try? c.decode(String.self, forKey: .name)

        // function_call: декодируем напрямую (без лишнего try?decodeIfPresent),
        // бросаем ошибку только если поле есть, но не декодируется.
        if c.contains(.functionCall) {
            self.functionCall = try? c.decode(AssistantFunctionCall.self, forKey: .functionCall)
        } else {
            self.functionCall = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Локальные поля (только для хранения, GigaChat игнорирует)
        try c.encode(id,                 forKey: .id)
        try c.encode(isTransitionMarker, forKey: .isTransitionMarker)
        try c.encode(isStageContext,     forKey: .isStageContext)
        try c.encode(timestamp,          forKey: .timestamp)
        // API-поля
        try c.encode(role,               forKey: .role)
        try c.encode(content,            forKey: .content)
        try c.encodeIfPresent(functionCall, forKey: .functionCall)
        try c.encodeIfPresent(name,         forKey: .name)
    }
}
