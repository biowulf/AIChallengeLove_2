//
//  SystemPromptPanelView.swift
//  AIChallengeLove_2
//

import SwiftUI

struct SystemPromptPanelView: View {
    @Bindable var viewModel: ChatDetailViewModel

    private var config: SystemPromptConfig {
        viewModel.memoryManager?.systemPromptConfig ?? SystemPromptConfig()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Prompt")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 4)

            Text("Определяет поведение ассистента: профиль, ограничения, стиль ответов и любые другие инструкции.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Активен", isOn: activeBinding)
                .tint(.green)

            Divider()

            TextEditor(text: promptBinding)
                .font(.system(.body, design: .monospaced))
                .padding(4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .frame(minHeight: 200)

            Divider()

            HStack {
                Button("Очистить") {
                    viewModel.updateSystemPromptConfig(SystemPromptConfig())
                }
                .font(.caption2)
                .foregroundColor(.red)

                Spacer()

                Text("\(config.customSystemPrompt.count) символов")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(width: 350)
        .background(Color.green.opacity(0.05))
    }

    // MARK: - Bindings

    private var promptBinding: Binding<String> {
        Binding(
            get: { config.customSystemPrompt },
            set: { newValue in
                var updated = config
                updated.customSystemPrompt = newValue
                viewModel.updateSystemPromptConfig(updated)
            }
        )
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { config.isActive },
            set: { newValue in
                var updated = config
                updated.isActive = newValue
                viewModel.updateSystemPromptConfig(updated)
            }
        )
    }
}
