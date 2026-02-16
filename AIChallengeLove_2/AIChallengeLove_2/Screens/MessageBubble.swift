//
//  MessageBubble.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/2/25.
//

import SwiftUI

struct MessageBubble: View {
    let message: Message

    var isUser: Bool {
        message.role == .user || message.role == .system
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer()
            }
            Text(message.content)
                .padding()
                .background(isUser ? Color.green.opacity(0.3) : Color.blue.opacity(0.3))
                .cornerRadius(10)
            if !isUser {
                Spacer()
            }
        }
    }
}
