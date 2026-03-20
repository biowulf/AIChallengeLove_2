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
        if message.isToolLog {
            toolLogView
        } else if message.isTransitionMarker {
            transitionMarkerView
        } else {
            regularMessageView
        }
    }

    // MARK: - Tool Log

    /// Лог вызова MCP-инструмента: виден в чате, в API не уходит.
    private var toolLogView: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.7))
                .frame(width: 3)
            Text(message.content)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    // MARK: - Transition Marker

    /// Информационная плашка о смене стадии задачи — показывается в чате но не отправляется в AI
    private var transitionMarkerView: some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.85), Color.blue.opacity(0.75)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
            Spacer()
        }
    }

    // MARK: - Regular message

    /// Форматированное время HH:mm
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.timestamp)
    }

    private var regularMessageView: some View {
        HStack(alignment: .top) {
            if isUser {
                Spacer()
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                Text(formattedContent)
                    .textSelection(.enabled)
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

                // Временна́я метка под пузырём
                Text(timeString)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            if !isUser {
                Spacer()
            }
        }
    }
}
