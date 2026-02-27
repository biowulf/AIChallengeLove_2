//
//  TypewriterText.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 26/2/26.
//

import SwiftUI

/// View для отображения текста из стрима
/// Показывает текст сразу без анимации, так как он уже приходит постепенно
struct TypewriterText: View {
    let fullText: String
    let isComplete: Bool
    
    var body: some View {
        Text(fullText)
            .textSelection(.enabled) // Позволяет выделять текст
            .animation(.none, value: fullText) // Отключаем анимацию
    }
}

/// View для анимации печатания текста с отменой предыдущих задач
/// Используйте это только для финальных сообщений, не для streaming!
struct AnimatedTypewriterText: View {
    let fullText: String
    let speed: Double = 0.03 // секунд на символ
    
    @State private var displayedText: String = ""
    @State private var animationTask: Task<Void, Never>?
    
    var body: some View {
        Text(displayedText)
            .textSelection(.enabled)
            .onChange(of: fullText) { oldValue, newValue in
                startAnimation(text: newValue)
            }
            .onAppear {
                if !fullText.isEmpty {
                    startAnimation(text: fullText)
                }
            }
            .onDisappear {
                animationTask?.cancel()
            }
    }
    
    private func startAnimation(text: String) {
        // Отменяем предыдущую анимацию
        animationTask?.cancel()
        
        // Сбрасываем текст
        displayedText = ""
        
        // Запускаем новую анимацию
        animationTask = Task {
            for character in text {
                // Проверяем, не отменена ли задача
                guard !Task.isCancelled else { return }
                
                displayedText.append(character)
                
                // Ждем перед следующим символом
                try? await Task.sleep(nanoseconds: UInt64(speed * 1_000_000_000))
            }
        }
    }
}

