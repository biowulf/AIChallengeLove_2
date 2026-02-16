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
                    InfoView()
                        .environment(viewModel)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            gptTypeButton

            clearChat

            Spacer()

            Button {
                viewModel.isShowInfo.toggle()
            } label: {
                Image(systemName: "exclamationmark.circle")
            }
            .padding()
        }
        .background(Color.gray.opacity(0.2))
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
                TextField("Сообщение...", text: $viewModel.inputText)
                    .padding()
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
