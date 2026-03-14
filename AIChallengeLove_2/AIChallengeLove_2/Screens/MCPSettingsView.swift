//
//  MCPSettingsView.swift
//  AIChallengeLove_2
//

import SwiftUI

struct MCPSettingsView: View {
    @Bindable var mcpManager: MCPManager
    @State private var showAddForm = false
    @State private var newName = ""
    @State private var newURL = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSection
                Divider()
                serversSection
                if showAddForm {
                    addServerForm
                }
                Spacer()
            }
            .padding()
            .frame(width: 300)
        }
        .background(Color.teal.opacity(0.04))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Model Context Protocol")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Text(mcpManager.isEnabled ? "Включён" : "Выключен")
                        .font(.system(size: 9))
                        .foregroundColor(mcpManager.isEnabled ? .teal : .secondary)
                    Toggle("", isOn: $mcpManager.isEnabled)
                        .tint(.teal)
                        .labelsHidden()
                        .onChange(of: mcpManager.isEnabled) { _, enabled in
                            if enabled {
                                Task { await mcpManager.connectAll() }
                            }
                        }
                }
                if mcpManager.isConnecting {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Подключение...")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Servers

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Серверы")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    withAnimation {
                        showAddForm.toggle()
                        newName = ""
                        newURL = ""
                    }
                } label: {
                    Image(systemName: showAddForm ? "xmark.circle.fill" : "plus.circle")
                        .foregroundColor(.teal)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(mcpManager.servers.indices), id: \.self) { index in
                serverRow(index: index)
            }
        }
    }

    private func serverRow(index: Int) -> some View {
        let server = mcpManager.servers[index]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor(for: server.id))
                    .frame(width: 8, height: 8)
                Text(server.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { mcpManager.servers[index].isEnabled },
                    set: { newValue in
                        mcpManager.servers[index].isEnabled = newValue
                        if newValue && mcpManager.isEnabled {
                            let config = mcpManager.servers[index]
                            Task { await mcpManager.connect(to: config) }
                        }
                    }
                ))
                .tint(.teal)
                .labelsHidden()

                Button {
                    mcpManager.removeServer(id: server.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if let status = mcpManager.status(for: server.id) {
                Text(status)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            let tools = mcpManager.tools(for: server.id)
            if !tools.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(tools) { tool in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 8))
                                .foregroundColor(.teal.opacity(0.7))
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tool.name)
                                    .font(.system(size: 9))
                                    .fontWeight(.medium)
                                if let desc = tool.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Add Server Form

    private var addServerForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Новый MCP сервер")
                .font(.caption)
                .fontWeight(.bold)

            TextField("Название", text: $newName)
                .font(.caption)
                .textFieldStyle(.roundedBorder)

            TextField("SSE URL", text: $newURL)
                .font(.caption)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 6) {
                Button {
                    guard !newName.trimmingCharacters(in: .whitespaces).isEmpty,
                          !newURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    mcpManager.addServer(name: newName, url: newURL)
                    if mcpManager.isEnabled, let config = mcpManager.servers.last {
                        Task { await mcpManager.connect(to: config) }
                    }
                    withAnimation { showAddForm = false }
                } label: {
                    Text("Добавить")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.teal.opacity(0.18))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { showAddForm = false }
                } label: {
                    Text("Отмена")
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
        .background(Color.teal.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func statusColor(for id: UUID) -> Color {
        guard let status = mcpManager.status(for: id) else { return .gray }
        if status.contains("Подключён") { return .green }
        if status.contains("Ошибка") { return .red }
        if status.contains("Получение") || status.contains("Подключение") { return .orange }
        return .gray
    }
}
