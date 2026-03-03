//
//  BranchPanelView.swift
//  AI_Challenge_Love_2
//

import SwiftUI

struct BranchPanelView: View {
    @Bindable var viewModel: ChatDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Линии диалога")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 4)

                if viewModel.dialogLines.isEmpty {
                    Text("Линии создаются автоматически при обсуждении разных тем")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.dialogLines) { line in
                        dialogLineRow(line)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .background(Color.purple.opacity(0.15))
        .frame(width: 270)
    }

    @ViewBuilder
    private func dialogLineRow(_ line: DialogLine) -> some View {
        let isActive = viewModel.activeLineId == line.id

        Button {
            viewModel.switchToLine(line.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isActive ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .font(.caption)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(line.topic)
                        .font(.subheadline)
                        .fontWeight(isActive ? .bold : .regular)
                        .lineLimit(2)

                    Text("\(line.messages.count) сообщ.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider().opacity(0.5)
    }
}
