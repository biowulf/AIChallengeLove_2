//
//  InfoView.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/15/25.
//

import SwiftUI

struct InfoView: View {
    @Bindable var viewModel: ChatDetailViewModel

    var body: some View {
        VStack(alignment: .leading) {
            // MARK: - Настройки запроса
            Text("Настройки:")
                .font(.title)
                .padding(.bottom, 6)

            HStack {
                Text("Max Tokens:")
                    .font(.headline)
                TextField("не ограничено", text: $viewModel.maxTokensText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .onChange(of: viewModel.maxTokensText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            viewModel.maxTokensText = filtered
                        }
                    }
            }
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("Temperature: \(String(format: "%.2f", viewModel.temperature))")
                    .font(.headline)
                Slider(value: $viewModel.temperature, in: 0...2, step: 0.01)
                    .tint(.blue)
            }
            .padding(.bottom, 20)

            Divider()
                .padding(.bottom, 10)

            // MARK: - Статистика
            Text("За запрос:")
                .font(.title)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text("GPT: \(viewModel.gptAPI.rawValue)")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text("Исходящие: \(viewModel.info.request[viewModel.gptAPI]?.input ?? 0)")
            Text("Моделью: \(viewModel.info.request[viewModel.gptAPI]?.output ?? 0)")
            Text("Всего токенов: \(viewModel.info.request[viewModel.gptAPI]?.total ?? 0)")
                .padding(.bottom, 30)

            Text("За сессию:")
                .font(.title)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text("GPT: \(viewModel.gptAPI.rawValue)")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text("Исходящие: \(viewModel.info.session[viewModel.gptAPI]?.input ?? 0)")
            Text("Моделью: \(viewModel.info.session[viewModel.gptAPI]?.output ?? 0)")
            Text("Всего токенов: \(viewModel.info.session[viewModel.gptAPI]?.total ?? 0)")

            Button("Сбросить сессию") {
                viewModel.clearSessionStats()
            }
            .padding(.top)
            .padding(.bottom, 30)

            Text("За всё время:")
                .font(.title)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text("GPT: \(viewModel.gptAPI.rawValue)")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text("Исходящие: \(viewModel.info.appSession[viewModel.gptAPI]?.input ?? 0)")
            Text("Моделью: \(viewModel.info.appSession[viewModel.gptAPI]?.output ?? 0)")
            Text("Всего токенов: \(viewModel.info.appSession[viewModel.gptAPI]?.total ?? 0)")

            if !viewModel.summaries.isEmpty {
                Divider()
                    .padding(.vertical, 10)

                Text("Контекст:")
                    .font(.title)
                    .padding(.bottom, 10)

                Text("Резюме: \(viewModel.summaries.count)")
                Text("Сообщений сжато: \(viewModel.summarizedUpToIndex)")
                Text("Всего сообщений: \(viewModel.messages.count)")
                Text("Режим: \(collapseTypeLabel(viewModel.collapseType))")
            }

            Spacer()
        }
        .padding()
        .background(Color.mint.opacity(0.2))
        .frame(width: 270)
    }

    private func collapseTypeLabel(_ type: CollapseType) -> String {
        switch type {
        case .none: return "Без сжатия"
        case .cut:  return "Обрезка"
        case .gpt:  return "AI-резюме"
        }
    }
}
