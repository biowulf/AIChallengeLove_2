//
//  StreamingUsageExample.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 26/2/26.
//

import Foundation

/*
 ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ STREAMING API
 
 1. В ChatDetailViewModel добавлено свойство `useStreaming: Bool` 
    для переключения между streaming и обычным режимом
 
 2. Streaming включается автоматически для GigaChat когда `useStreaming = true`
 
 3. Во время streaming:
    - `isStreaming` = true - идет прием данных
    - `streamingText` - содержит текущий накопленный текст
    - `isStreamingComplete` = true - когда весь текст получен
 
 4. UI автоматически показывает:
    - Анимацию печатания текста (TypewriterText) когда приходят данные
    - Анимированные точки "Думает..." когда ждем первого чанка
    - Блокировку кнопки отправки во время streaming
 
 СТРУКТУРА STREAMING RESPONSE:
 
 Server-Sent Events формат:
 ```
 data: {"choices":[{"delta":{"content":"Привет"},"index":0}],"created":1234567890,"model":"GigaChat"}
 
 data: {"choices":[{"delta":{"content":" как"},"index":0}],"created":1234567890,"model":"GigaChat"}
 
 data: {"choices":[{"delta":{"content":" дела?"},"index":0,"finish_reason":"stop"}],"usage":{...}}
 
 data: [DONE]
 ```
 
 АНИМАЦИЯ:
 
 TypewriterText - анимирует появление каждого символа с задержкой 0.03 секунды
 ThinkingDots - показывает от 0 до 3 точек с интервалом 0.5 секунды
 
 ПЕРЕКЛЮЧЕНИЕ РЕЖИМОВ:
 
 В header ChatDetailView есть Toggle "Streaming" который доступен только для GigaChat
 */
