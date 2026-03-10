//
//  TaskState.swift
//  AIChallengeLove_2
//

import Foundation

// MARK: - Стадии задачи

enum TaskPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case research
    case plan
    case executing
    case validation
    case report
    case done

    var label: String {
        switch self {
        case .idle:       return "Нет задачи"
        case .research:   return "Research"
        case .plan:       return "Plan"
        case .executing:  return "Executing"
        case .validation: return "Validation"
        case .report:     return "Report"
        case .done:       return "Done"
        }
    }

    var emoji: String {
        switch self {
        case .idle:       return "⬜"
        case .research:   return "🔍"
        case .plan:       return "📋"
        case .executing:  return "⚙️"
        case .validation: return "✅"
        case .report:     return "📝"
        case .done:       return "🏁"
        }
    }

    var phaseDescription: String {
        switch self {
        case .idle:       return "Нет активной задачи"
        case .research:   return "Исследование задачи, кодовой базы, зависимостей"
        case .plan:       return "Формирование плана реализации"
        case .executing:  return "Написание кода"
        case .validation: return "Проверка результата (тесты, ревью, сборка)"
        case .report:     return "Отчёт о проделанной работе"
        case .done:       return "Задача завершена"
        }
    }

    /// Маркер, который AI пишет в конце ответа для предложения перехода
    var completionMarker: String {
        switch self {
        case .research:   return "ИССЛЕДОВАНИЕ ЗАВЕРШЕНО"
        case .plan:       return "ПЛАН ГОТОВ"
        case .executing:  return "ВЫПОЛНЕНИЕ ЗАВЕРШЕНО"
        case .validation: return "ПРОВЕРКА ПРОЙДЕНА"
        case .report:     return "ОТЧЁТ ГОТОВ"
        default:          return ""
        }
    }

    /// Основной следующий шаг (для авто-перехода по маркеру)
    var primaryNextPhase: TaskPhase? {
        switch self {
        case .research:   return .plan
        case .plan:       return .executing
        case .executing:  return .validation
        case .validation: return .done      // Validation → Done напрямую
        case .report:     return .done
        default:          return nil
        }
    }
}

// MARK: - Шаг задачи

struct TaskStep: Codable, Sendable, Identifiable {
    let id: UUID
    var description: String
    var isCompleted: Bool

    init(id: UUID = UUID(), description: String, isCompleted: Bool = false) {
        self.id = id
        self.description = description
        self.isCompleted = isCompleted
    }
}

// MARK: - Запись перехода

struct TaskPhaseTransition: Codable, Sendable {
    let from: TaskPhase
    let to: TaskPhase
    let reason: String
    let timestamp: Date

    init(from: TaskPhase, to: TaskPhase, reason: String = "", timestamp: Date = Date()) {
        self.from = from
        self.to = to
        self.reason = reason
        self.timestamp = timestamp
    }
}

// MARK: - Состояние задачи

struct TaskState: Codable, Sendable {
    var currentPhase: TaskPhase
    var taskDescription: String
    var steps: [TaskStep]
    var currentStepIndex: Int
    var history: [TaskPhaseTransition]
    var updatedAt: Date

    /// Предложенный следующий шаг (ожидает подтверждения пользователем или авто-перехода)
    var pendingTransition: TaskPhase?

    init(
        currentPhase: TaskPhase = .idle,
        taskDescription: String = "",
        steps: [TaskStep] = [],
        currentStepIndex: Int = 0,
        history: [TaskPhaseTransition] = [],
        updatedAt: Date = Date(),
        pendingTransition: TaskPhase? = nil
    ) {
        self.currentPhase = currentPhase
        self.taskDescription = taskDescription
        self.steps = steps
        self.currentStepIndex = currentStepIndex
        self.history = history
        self.updatedAt = updatedAt
        self.pendingTransition = pendingTransition
    }

    var isEmpty: Bool { currentPhase == .idle && taskDescription.isEmpty }
    var isActive: Bool { currentPhase != .idle && currentPhase != .done }

    /// Форматирует состояние задачи для system prompt
    func asSystemPromptText() -> String {
        guard !isEmpty else { return "" }
        var parts: [String] = []
        parts.append("Текущая задача: \(taskDescription)")
        parts.append("Стадия: \(currentPhase.emoji) \(currentPhase.label) — \(currentPhase.phaseDescription)")
        if !steps.isEmpty {
            let stepsText = steps.enumerated().map { idx, step in
                let marker = step.isCompleted ? "[x]" : (idx == currentStepIndex ? "[>]" : "[ ]")
                return "\(marker) \(step.description)"
            }.joined(separator: "\n")
            parts.append("Шаги:\n\(stepsText)")
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Ошибка перехода

enum TransitionError: Error, LocalizedError {
    case invalidTransition(from: TaskPhase, to: TaskPhase, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidTransition(_, _, let reason):
            return reason
        }
    }
}

// MARK: - Конечный автомат переходов

struct TaskStateMachine {

    /// Допустимые переходы из каждой стадии.
    /// Строго по спецификации — перескакивать стадии ЗАПРЕЩЕНО.
    ///
    ///   Research  → Plan, Executing
    ///   Plan      → Executing
    ///   Executing → Validation, Research
    ///   Validation→ Report, Executing, Research
    ///   Report    → Done
    ///   Done      → idle, Research (сброс / новая задача)
    static let allowedTransitions: [TaskPhase: Set<TaskPhase>] = [
        .idle:       [.research],
        .research:   [.plan, .executing],
        .plan:       [.executing],
        .executing:  [.validation, .research],
        .validation: [.done, .report, .executing, .research],
        .report:     [.done],
        .done:       [.idle, .research]
    ]

    /// Пытается выполнить переход. Возвращает .success или .failure с описанием ошибки.
    @discardableResult
    static func tryTransition(
        from current: TaskPhase,
        to target: TaskPhase,
        state: inout TaskState
    ) -> Result<Void, TransitionError> {

        guard let allowed = allowedTransitions[current], allowed.contains(target) else {
            let allowed = allowedTransitions[current]?.map(\.label).sorted().joined(separator: ", ") ?? "нет"
            return .failure(.invalidTransition(
                from: current,
                to: target,
                reason: "Переход \(current.label) → \(target.label) запрещён. Допустимые: \(allowed)"
            ))
        }

        state.history.append(TaskPhaseTransition(from: current, to: target))
        state.currentPhase = target
        state.pendingTransition = nil
        state.updatedAt = Date()

        // При сбросе в idle — очищаем данные задачи
        if target == .idle {
            state.steps.removeAll()
            state.currentStepIndex = 0
            state.taskDescription = ""
        }

        return .success(())
    }

    /// Проверяет допустимость перехода (без изменения состояния)
    static func canTransition(from current: TaskPhase, to target: TaskPhase) -> Bool {
        allowedTransitions[current]?.contains(target) ?? false
    }
}
