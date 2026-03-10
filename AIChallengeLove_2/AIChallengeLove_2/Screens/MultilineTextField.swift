//
//  MultilineTextField.swift
//  AIChallengeLove_2
//

import SwiftUI
import AppKit

/// Многострочное поле ввода для macOS.
/// Enter — отправить (вызывает onSubmit).
/// Shift+Enter — перенос строки.
struct MultilineTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = context.coordinator.textView
        textView.delegate = context.coordinator

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = false
        // Убираем автоматический перенос строки внутри поля
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.parent = self

        // Обновляем текст только если он реально изменился (избегаем цикл)
        if textView.string != text {
            let savedRange = textView.selectedRange()
            textView.string = text
            let clampedLoc = min(savedRange.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLoc, length: 0))
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineTextField
        let textView = NSTextView()
        var onSubmit: () -> Void

        init(_ parent: MultilineTextField) {
            self.parent = parent
            self.onSubmit = parent.onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Prevent feedback loop
            if parent.text != tv.string {
                parent.text = tv.string
            }
        }

        /// Перехватываем Enter / Shift+Enter
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let isShift = NSEvent.modifierFlags.contains(.shift)
                if isShift {
                    // Shift+Enter → обычный перенос строки
                    return false
                } else {
                    // Enter → отправить
                    onSubmit()
                    return true
                }
            }
            return false
        }
    }
}
