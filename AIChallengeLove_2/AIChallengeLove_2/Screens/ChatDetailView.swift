//
//  ChatDetailView.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/2/25.
//

import SwiftUI
import SwiftData

struct ChatDetailView: View {
    @Bindable var viewModel: ChatDetailViewModel

    init(viewModel: ChatDetailViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading) {
            header
            HStack {
                chatView
                if viewModel.isShowInfo {
                    InfoView(viewModel: viewModel)
                }
            }
        }
    }

    private var header: some View {
        VStack {
            HStack {
                gptTypeButton

                clearChat

                Spacer()

                Toggle("Ограничение ответа", isOn: $viewModel.isStrictMode)
                    .tint(.orange)

                Button {
                    viewModel.isShowInfo.toggle()
                } label: {
                    Image(systemName: "exclamationmark.circle")
                }
                .padding()
            }
            .background(Color.gray.opacity(0.2))

            if viewModel.isStrictMode {
                Text("Режим: Формат + Лимит 20 слов + Stop-слово")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.vertical, 4)
            }
        }
    }

    private var chatView: some View {
        VStack {
            // Список сообщений
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages.indices, id: \.self) { index in
                        MessageBubble(message: viewModel.messages[index])
                    }
                    if viewModel.isLoading {
                        LoadingDots()
                    }
                }
                .padding()
            }

            // Поле ввода и кнопка отправки
            HStack {
                TextField("Сообщение...", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...5) // Минимум 1 строка, максимум 5, далее — скролл
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)

                Button(action: viewModel.sendMessage) {
                    Text("Отправить")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }


    private var gptTypeButton: some View {
        Button {
            viewModel.isActiveDialog = true
        } label: {
            HStack {
                Text(viewModel.gptAPI.rawValue)
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .padding(.leading, 2)
            }
        }
        .padding()
        .confirmationDialog("", isPresented: $viewModel.isActiveDialog) {
            ForEach(GPTAPI.allCases, id: \.self) { api in
                Button(role: (api == .yandex) ? .cancel : .confirm) {
                    viewModel.gptAPI = api
                    viewModel.messages = []
                } label: {
                    HStack {
                        Text(api.rawValue)
                        if api == viewModel.gptAPI {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .padding(.leading, 2)
                        }
                    }
                }
            }
        }
    }

    private var clearChat: some View {
        Button {
            viewModel.clearChat()
        } label: {
            HStack {
                Text("Сбросить")
            }
        }
        .padding()
    }
}
