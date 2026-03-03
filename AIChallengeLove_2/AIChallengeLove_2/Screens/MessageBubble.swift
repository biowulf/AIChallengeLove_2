//
//  MessageBubble.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/2/25.
//

import SwiftUI
import AppKit

struct MessageBubble: View {
    let message: Message

    @State private var isHovered = false
    @State private var showCopied = false

    var isUser: Bool {
        message.role == .user || message.role == .system
    }

    private var formattedContent: AttributedString {
        (try? AttributedString(
            markdown: message.content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.content)
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser {
                Spacer()
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
                Text(formattedContent)
                    .textSelection(.enabled)
            }
            .padding()
            .background(isUser ? Color.green.opacity(0.3) : Color.blue.opacity(0.3))
            .cornerRadius(10)
            .overlay(alignment: isUser ? .bottomLeading : .bottomTrailing) {
                if isHovered {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopied = false
                        }
                    } label: {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(showCopied ? .green : .secondary)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .offset(x: isUser ? -4 : 4, y: 4)
                    .transition(.opacity)
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            if !isUser {
                Spacer()
            }
        }
    }
}
