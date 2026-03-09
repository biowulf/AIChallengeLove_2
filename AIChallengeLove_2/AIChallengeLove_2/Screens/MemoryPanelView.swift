//
//  MemoryPanelView.swift
//  AIChallengeLove_2
//

import SwiftUI

struct MemoryPanelView: View {
    @Bindable var viewModel: ChatDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Слои памяти")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 4)

                // MARK: - Layer 1: Краткосрочная память
                shortTermSection

                Divider()

                // MARK: - Layer 2: Рабочая память
                workingMemorySection

                Divider()

                // MARK: - Layer 3: Долговременная память
                longTermMemorySection

                Spacer()
            }
            .padding()
        }
        .background(Color.cyan.opacity(0.15))
        .frame(width: 270)
    }

    // MARK: - Short-term Memory Section

    private var shortTermSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.blue)
                Text("Краткосрочная")
                    .font(.headline)
            }

            Text("Окно: последние \(viewModel.contextWindowSize) сообщений")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Всего в диалоге: \(viewModel.effectiveMessages().count)")
                .font(.caption)
                .foregroundColor(.secondary)

            let windowMessages = viewModel.memoryManager?.shortTermMemory
                .recentMessages(from: viewModel.effectiveMessages()) ?? []
            Text("В окне сейчас: \(windowMessages.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Working Memory Section

    private var workingMemorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "gearshape.2")
                    .foregroundColor(.orange)
                Text("Рабочая")
                    .font(.headline)
                Spacer()
                Button("Очистить") {
                    viewModel.memoryManager?.clearConversationMemory()
                }
                .font(.caption2)
            }

            if let wm = viewModel.memoryManager?.workingMemory, !wm.isEmpty {
                if !wm.currentGoal.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("Задача:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        Text(wm.currentGoal)
                            .font(.caption)
                    }
                }

                if !wm.activeTopic.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text("Тема:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        Text(wm.activeTopic)
                            .font(.caption)
                    }
                }

                if !wm.entities.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Сущности:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        ForEach(wm.entities, id: \.self) { entity in
                            Text("  \u{2022} \(entity)")
                                .font(.caption)
                        }
                    }
                }

                if !wm.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Заметки:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        ForEach(wm.notes, id: \.self) { note in
                            Text("  \u{2022} \(note)")
                                .font(.caption)
                        }
                    }
                }
            } else {
                Text("Пока пуста — заполнится после первого обмена")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Long-term Memory Section

    private var longTermMemorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                Text("Долговременная")
                    .font(.headline)
                Spacer()
                Button("Очистить") {
                    viewModel.clearLongTermMemory()
                }
                .font(.caption2)
                .foregroundColor(.red)
            }

            if let ltm = viewModel.memoryManager?.longTermMemory, !ltm.isEmpty {
                ForEach(LongTermCategory.allCases, id: \.self) { category in
                    let entries = ltm.entries.filter { $0.category == category }
                    if !entries.isEmpty {
                        Text(category.label)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                            .padding(.top, 2)

                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 4) {
                                Text(entry.key + ":")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(entry.value)
                                    .font(.caption)
                            }
                        }
                    }
                }

                if let lastExtraction = ltm.lastExtractionAt {
                    Text("Обновлено: \(lastExtraction.formatted(.dateTime.hour().minute()))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            } else {
                Text("Пока пуста — накопится со временем")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
