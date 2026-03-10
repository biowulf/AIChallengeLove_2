//
//  TaskPanelView.swift
//  AIChallengeLove_2
//

import SwiftUI

struct TaskPanelView: View {
    @Bindable var viewModel: ChatDetailViewModel
    @State private var isHistoryExpanded = false

    /// Реактивный taskState берём прямо из viewModel (не через memoryManager)
    private var taskState: TaskState {
        viewModel.taskState
    }

    // Порядок стадий для отображения прогресса
    private let pipeline: [TaskPhase] = [.research, .plan, .executing, .validation, .report, .done]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                // Заголовок + переключатели
                headerSection

                Divider()

                // Пайплайн стадий
                if !taskState.isEmpty {
                    pipelineView
                    Divider()
                }

                // Основной контент
                if taskState.isEmpty {
                    emptyStateSection
                } else {
                    activeTaskSection
                }

                // Pending transition — подтверждение пользователем
                if !viewModel.isAutoTransition, let pending = taskState.pendingTransition {
                    pendingTransitionSection(pending)
                }

                // Ошибка перехода
                if let error = viewModel.taskTransitionError {
                    errorView(error)
                }

                // Сброс
                if !taskState.isEmpty {
                    Divider()
                    Button("🗑 Сбросить задачу") {
                        viewModel.resetTask()
                    }
                    .font(.caption2)
                    .foregroundColor(.red)
                }

                // История переходов
                if !taskState.history.isEmpty {
                    Divider()
                    historySection
                }

                Spacer()
            }
            .padding()
            .frame(width: 280)
        }
        .background(Color.yellow.opacity(0.04))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Задача")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                // Переключатели режимов
                VStack(alignment: .trailing, spacing: 4) {
                    // Режим задачи (on/off)
                    HStack(spacing: 4) {
                        Text("Режим")
                            .font(.system(size: 9))
                            .foregroundColor(viewModel.isTaskModeEnabled ? .orange : .secondary)
                        Toggle("", isOn: $viewModel.isTaskModeEnabled)
                            .tint(.orange)
                            .labelsHidden()
                    }
                    // Авто / Ручной переход
                    HStack(spacing: 4) {
                        Text(viewModel.isAutoTransition ? "Авто" : "Ручной")
                            .font(.system(size: 9))
                            .foregroundColor(viewModel.isAutoTransition ? .blue : .secondary)
                        Toggle("", isOn: $viewModel.isAutoTransition)
                            .tint(.blue)
                            .labelsHidden()
                    }
                }
            }

            if !taskState.isEmpty {
                // Текущая стадия badge
                HStack(spacing: 6) {
                    Text(taskState.currentPhase.emoji)
                    Text(taskState.currentPhase.label)
                        .fontWeight(.semibold)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(taskState.currentPhase.phaseDescription)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(currentPhaseColor.opacity(0.12))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Pipeline progress

    private var pipelineView: some View {
        HStack(spacing: 0) {
            ForEach(Array(pipeline.enumerated()), id: \.offset) { index, phase in
                VStack(spacing: 3) {
                    Circle()
                        .fill(pipelineNodeColor(phase))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Text(phase.emoji)
                                .font(.system(size: 8))
                        )
                    Text(phase.label)
                        .font(.system(size: 7))
                        .foregroundColor(isPipelineReached(phase) ? .primary : .secondary)
                        .lineLimit(1)
                }

                if index < pipeline.count - 1 {
                    Rectangle()
                        .fill(isTransitionAllowed(from: phase, to: pipeline[index + 1]) ?
                              Color.green.opacity(0.5) : Color.gray.opacity(0.2))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 14)
                }
            }
        }
    }

    private func pipelineNodeColor(_ phase: TaskPhase) -> Color {
        if phase == taskState.currentPhase {
            return currentPhaseColor
        }
        if isPipelineReached(phase) {
            return .green.opacity(0.6)
        }
        return .gray.opacity(0.25)
    }

    private func isPipelineReached(_ phase: TaskPhase) -> Bool {
        guard let currentIdx = pipeline.firstIndex(of: taskState.currentPhase),
              let phaseIdx = pipeline.firstIndex(of: phase) else { return false }
        return phaseIdx <= currentIdx
    }

    private func isTransitionAllowed(from: TaskPhase, to: TaskPhase) -> Bool {
        TaskStateMachine.canTransition(from: from, to: to)
    }

    // MARK: - Empty state

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isTaskModeEnabled {
                Label("Режим задачи включён", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Напишите задачу в чате — она автоматически запустит стадийный поток Research → Plan → Executing → Validation → Report → Done.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Режим задачи выключен", systemImage: "circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Включите переключатель «Режим» выше, затем напишите задачу в чат.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Active task

    private var activeTaskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !taskState.taskDescription.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Задача:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Text(taskState.taskDescription)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !taskState.steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Шаги:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    ForEach(Array(taskState.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: step.isCompleted ? "checkmark.circle.fill" :
                                    (index == taskState.currentStepIndex ? "arrow.right.circle.fill" : "circle"))
                                .foregroundColor(step.isCompleted ? .green :
                                    (index == taskState.currentStepIndex ? .blue : .gray))
                                .font(.caption)
                            Text(step.description)
                                .font(.caption)
                                .foregroundColor(step.isCompleted ? .secondary : .primary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Pending transition

    private func pendingTransitionSection(_ targetPhase: TaskPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI предлагает переход:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(taskState.currentPhase.emoji) \(taskState.currentPhase.label) → \(targetPhase.emoji) \(targetPhase.label)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }

            HStack(spacing: 6) {
                Button {
                    viewModel.transitionTask(to: targetPhase)
                } label: {
                    Label("Подтвердить", systemImage: "checkmark.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.18))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.clearPendingTransition()
                } label: {
                    Label("Отклонить", systemImage: "xmark.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
            Text(error)
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation { isHistoryExpanded.toggle() }
            } label: {
                HStack {
                    Text("История переходов (\(taskState.history.count))")
                        .font(.caption)
                        .fontWeight(.bold)
                    Spacer()
                    Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)

            if isHistoryExpanded {
                ForEach(Array(taskState.history.enumerated().reversed()), id: \.offset) { _, transition in
                    HStack(spacing: 4) {
                        Text(transition.from.emoji + transition.from.label)
                            .font(.system(size: 9))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                        Text(transition.to.emoji + transition.to.label)
                            .font(.system(size: 9))
                        if !transition.reason.isEmpty {
                            Text("(\(transition.reason))")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(transition.timestamp.formatted(.dateTime.hour().minute()))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var currentPhaseColor: Color {
        switch taskState.currentPhase {
        case .idle:       return .gray
        case .research:   return .orange
        case .plan:       return .yellow
        case .executing:  return .green
        case .validation: return .blue
        case .report:     return .purple
        case .done:       return .gray
        }
    }
}
